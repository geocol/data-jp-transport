use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use AnyEvent;
use AnyEvent::MediaWiki::Source;
use Web::DOM::Document;
use Web::HTML::Table;
use Text::MediaWiki::Parser;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

sub extract_from_doc ($) {
  my $doc = $_[0];
  my $data = [];
  my $h1 = $doc->query_selector ('h1:-manakai-contains("駅一覧"), h1:-manakai-contains("電停一覧")');
    if (defined $h1) {
        my $section = $h1->parent_node;
        my $table = $section ? $section->get_elements_by_tag_name ('table')->[0] : undef;
        if (defined $table) {
            my $tbl = Web::HTML::Table->new;
            my $t = $tbl->form_table ($table);
            my $label_to_i = {};
            for (0..$#{$t->{column}}) {
                my $el = $t->{cell}->[$_]->[0]->[0]->{element} or next;
                my $text = $el->text_content;
                $text =~ s/\A\s+//;
                $text =~ s/\s+\z//;
                $text =~ s/\s+/ /g;
                $label_to_i->{$text} = $_;
            }
            my $i = $label_to_i->{駅名} //
                    $label_to_i->{"駅名・信号場名"} //
                    $label_to_i->{[grep { /駅/ } keys %$label_to_i]->[0] || '駅'} //
                    0;
            for my $y (0..$#{$t->{row}}) {
                my $cell = $t->{cell}->[$i]->[$y]->[0] or next;
                next unless $cell->{element}->local_name eq 'td';
                next if $cell->{x} != $i;
                next if $cell->{y} != $y;

                my $l;
                for my $el (@{$cell->{element}->children}) {
                    next unless $el->local_name eq 'l';
                    next if $el->has_attribute ('embed');
                    $l = $el;
                    last;
                }

                my $d = {};
                if (defined $l) {
                    $d->{name} = $l->text_content;
                    my $n = $l->get_attribute ('wref');
                    $d->{wref} = $n if defined $n;
                } else {
                    my $name = $cell->{element}->text_content;
                    $name =~ s/\A\s+//;
                    $name =~ s/\s+\z//;
                    $name =~ s/\s+/ /g;
                    $d->{name} = $name;
                }
                if (defined $label_to_i->{駅番号}) {
                    my $cell = $t->{cell}->[$label_to_i->{駅番号}]->[$y]->[0];
                    if ($cell) {
                        my $num = $cell->{element}->text_content;
                        $num =~ s/\A\s+//;
                        $num =~ s/\s+\z//;
                        $num =~ s/\s+/ /g;
                        $d->{number} = $num if length $num;
                    }
                }
                push @$data, $d;
            }
        } else { # no table
            my $ls = $section->query_selector_all ('l');
            for (@$ls) {
                my $name = $_->text_content;
                if ($name =~ /(?:駅|信号所|電停|停留所|仮乗降場)$/) {
                    my $wref = $_->get_attribute ('wref');
                    my $d = {name => $name};
                    $d->{wref} = $wref if defined $wref;
                    push @$data, $d;
                }
            }

        }
    }
    return $data;
} # extract_from_doc

my $Data = do {
    my $f = file (__FILE__)->dir->parent->file ('intermediate', 'railway-lines.json');
    file2perl $f;
};

my $root_d = file (__FILE__)->dir->parent;
my $mw = AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
    ($root_d->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml'),
     $root_d->subdir ('local', 'cache'));

select STDERR;
$| = 1;
select STDOUT;

my $cv = AE::cv;

$cv->begin;
for my $key (keys %$Data) {
  $cv->begin;
  $mw->get_source_text_by_name_as_cv ($Data->{$key}->{wref})->cb (sub {
    my $data = $_[0]->recv;
    print STDERR ".";
    if (defined $data) {
      my $doc = new Web::DOM::Document;
      my $parser = Text::MediaWiki::Parser->new;
      $parser->parse_char_string ($data => $doc);
      my $data = extract_from_doc $doc;
      $Data->{$key}->{stations} = $data;
    } else {
      warn "No data: |$Data->{$key}->{wref}|\n";
    }
    $cv->end;
  });
}
$cv->end;

$cv->cb (sub {
  print STDERR " done\n";
  print perl2json_bytes_for_record $Data;
});

$cv->recv;

## See also:
##   Wikipedia:記事名の付け方/鉄道
##   <http://ja.wikipedia.org/wiki/Wikipedia:%E8%A8%98%E4%BA%8B%E5%90%8D%E3%81%AE%E4%BB%98%E3%81%91%E6%96%B9/%E9%89%84%E9%81%93>
