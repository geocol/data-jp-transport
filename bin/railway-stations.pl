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
use Char::Normalize::FullwidthHalfwidth qw(get_fwhw_normalized);

my $Symbols = qr{[*\x{25C7}\x{25A0}]};

sub _tc ($);
sub _tc ($) {
  my $el = $_[0];
  my $text = '';
  for (@{$el->child_nodes}) {
    if ($_->node_type == $_->ELEMENT_NODE) {
      my $ln = $_->local_name;
      if ($ln eq 'comment' or $ln eq 'ref') {
        #
      } elsif ($ln eq 'include') {
        my $wref = $_->get_attribute ('wref');
        if ($wref eq 'Color' or $wref eq 'color') {
          my @ip = grep { $_->local_name eq 'iparam' } @{$_->children};
          $text .= _tc $ip[1];
        } else {
          $text .= _tc $_;
        }
      } else {
        $text .= _tc $_;
      }
    } elsif ($_->node_type == $_->TEXT_NODE) {
      $text .= $_->data;
    }
  }
  return $text;
} # _tc

sub extract_from_doc ($$) {
  my ($page_name, $doc) = @_;
  my $data = [];
  my $h1 = $doc->query_selector ('h1:-manakai-contains("駅一覧"), h1:-manakai-contains("電停一覧"), h1:-manakai-contains("駅・信号場一覧")');

  my $has_ruby = {鹿児島市電唐湊線 => 1}->{$page_name};

  if (defined $h1) {
    my $section = $h1->parent_node;
    for my $h1 (@{$section->query_selector_all ('h1:-manakai-contains("未開業区間"), h1:-manakai-contains("配線図"), h1:-manakai-contains("構造"), h1:-manakai-contains("過去の"), h1:-manakai-contains("廃止"), h1:-manakai-contains("比較表")')}) {
      $h1->parent_node->parent_node->remove_child ($h1->parent_node);
    }
    my $tables = $section->get_elements_by_tag_name ('table');
    if (@$tables) {
      my %found;
      for my $table (@$tables) {
        my $tbl = Web::HTML::Table->new;
        my $t = $tbl->form_table ($table);
        my $label_to_i = {};
        for (0..$#{$t->{column}}) {
          my $cell = $t->{cell}->[$_]->[0]->[0] or next;
          my $el = $cell->{element};
          my $text = _tc $el;
          $text =~ s/\A\s+//;
          $text =~ s/\s+\z//;
          $text =~ s/\s+/ /g;
          $label_to_i->{$text} //= $_;
        }
        my $i = $label_to_i->{駅名} //
            $label_to_i->{"駅名・信号場名"} //
            $label_to_i->{電停名} //
            $label_to_i->{[grep { /駅|電停名/ } keys %$label_to_i]->[0] || '駅'} //
            0;
        $i = 1 if $page_name eq '真岡鐵道真岡線' and $i == 0;
        $i = 1 if $page_name eq '秋田内陸縦貫鉄道秋田内陸線' and $i == 0;
        $i = 1 if $page_name eq '赤羽線' and $i == 0;
        my $i_info = $label_to_i->{[grep { /備考/ } keys %$label_to_i]->[0] || '備考'};

        my $suffix = {
          鹿児島市電谷山線 => '電停',
          広島電鉄宇品線 => '電停',
          広島電鉄本線 => '電停',
          広島電鉄横川線 => '電停',
          広島電鉄江波線 => '電停',
          広島電鉄白島線 => '電停',
          広島電鉄皆実線 => '電停',
          万葉線高岡軌道線 => '停留場',
          万葉線新湊港線 => '駅',
        }->{$page_name} || '';
        if ($page_name eq '鹿児島市電谷山線' and $i == 0) {
          $i = $#{$t->{column}};
        }
        my $abandoned_area = {名鉄美濃町線 => 1,
                              名鉄揖斐線 => 1}->{$page_name};
        my $in_progress_area;
        for my $y (0..$#{$t->{row}}) {
          my $cell = $t->{cell}->[$i]->[$y]->[0] or next;

          if ($cell->{width} > 1 and $cell->{width} == @{$t->{column}}) {
            my $cell_data = $cell->{element}->text_content;
            if ($cell_data =~ /廃止区間/) {
              ## <http://ja.wikipedia.org/wiki/%E3%81%AE%E3%81%A8%E9%89%84%E9%81%93%E4%B8%83%E5%B0%BE%E7%B7%9A>
              $abandoned_area = 1;
            } elsif ($cell_data =~ /未開業区間|計画中/) {
              $in_progress_area = 1;
            }
            next;
          }
          next if $in_progress_area;
          next if $cell->{x} != $i;
          next if $cell->{y} != $y;
          next unless $cell->{element}->local_name eq 'td';

          my $l;
          for my $el (@{$cell->{element}->children}) {
            next unless $el->local_name eq 'l';
            next if $el->has_attribute ('embed');
            next if $el->text_content eq '臨';
            $l = $el;
            last;
          }

          my $d = {};
          my $cell_content = get_fwhw_normalized _tc $cell->{element};
          if ($page_name eq '東北本線' and not $cell_content =~ /駅/) {
            ## <http://ja.wikipedia.org/wiki/%E6%9D%B1%E5%8C%97%E6%9C%AC%E7%B7%9A>
            next;
          }

          if (defined $l) {
            $d->{name} = _tc $l;
            my $n = $l->get_attribute ('wref');
            $d->{wref} = $n if defined $n;

            my $nn = get_fwhw_normalized $d->{name};
            if (not $nn eq $d->{name}) {
              if (not defined $d->{wref}) {
                $d->{wref} = $d->{name};
              }
              $d->{name} = $nn;
            }

            $d->{abandoned} = 1
                if $abandoned_area or $cell_content =~ /廃止/;
          } else {
            my $name = $cell_content;
            $name =~ s/^\s*#[0-9A-Fa-f]+\s*//;
            $d->{abandoned} = 1
                if $name =~ s/\s*[(]廃止[)]\s*$// or $abandoned_area;
            if ($name =~ m{^\s*[(][^()]+[)]\s*(.+)$}) {
              $name = $1;
            }
            if ($name =~ m{^\((.+信号所)\)$}) {
              $name = $1;
            }
            $name =~ s/$Symbols+\s*\z//o;
            $name =~ s/^\s*\*\s*//;
            $name =~ s/\A\s+//;
            $name =~ s/\s+\z//;
            $name =~ s/\s+/ /g;
            next unless length $name;
            $d->{name} = $name;
          }
                if (length $suffix and not $d->{name} =~ /$suffix$/) {
                  $d->{wref} = $d->{name} if not defined $d->{wref};
                  $d->{name} .= $suffix;
                }
                if (defined $d->{wref} and $d->{wref} =~ /^\#/) {
                    $d->{wref} = $page_name . $d->{wref};
                }

                if (defined $label_to_i->{駅番号} or
                    defined $label_to_i->{電停番号}) {
                  my $cell = $t->{cell}->[$label_to_i->{駅番号} // $label_to_i->{電停番号}]->[$y]->[0];
                  if ($cell) {
                    my $num = get_fwhw_normalized _tc $cell->{element};
                    $num =~ s/\A\s+//;
                    $num =~ s/\s+\z//;
                    $num =~ s/\s+/ /g;
                    $d->{number} = $num if length $num and $num =~ /\S/ and $num ne '-';
                  }
                }

                if (defined $i_info) {
                  my $info_cell = $t->{cell}->[$i_info]->[$y]->[0];
                  if ($info_cell) {
                    my $info = $info_cell->{element}->text_content;
                    if ($info =~ /廃止/) {
                      $d->{abandoned} = 1;
                    }
                  }
                }

          next if $d->{name} =~ /接続点|分界点|分岐点/;
          next if $found{$d->{name}};
          $found{$d->{name}}++;
          push @$data, $d;
        } # row
      } # $table
    } else { # no table
      my $ls = $section->query_selector_all ('l');
      for (@$ls) {
        next if $_->has_attribute ('embed');
        my $name = $_->text_content;
        if ($name =~ /(?:駅|信号所|電停|停留所|仮乗降場)$/) {
          my $wref = $_->get_attribute ('wref');
          my $d = {name => $name};
          $d->{wref} = $wref if defined $wref;
          my $nn = get_fwhw_normalized $d->{name};
          if (not $nn eq $d->{name}) {
            if (not defined $d->{wref}) {
              $d->{wref} = $d->{name};
            }
            $d->{name} = $nn;
          }
          if ($has_ruby and $d->{name} =~ /[(]/) {
            $d->{wref} = $d->{name} if not defined $d->{wref};
            $d->{name} =~ s/\s*[(][^()]+[)]\s*//g;
          }
          push @$data, $d;
        }
      }
    } # table
  }
  return $data;
} # extract_from_doc

my @line = map { tr/_/ /; decode 'utf-8', $_ } @ARGV;
my $force_update = @ARGV;

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'railway-stations.json');
my $Data = file2perl $data_f;

my $lines_f = file (__FILE__)->dir->parent->file ('intermediate', 'railway-lines.json');
my $LinesData = file2perl $lines_f;

@line = keys %$LinesData unless @line;

my $root_d = file (__FILE__)->dir->parent;
my $mw = AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
    ($root_d->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml'),
     $root_d->subdir ('local', 'cache'));

select STDERR;
$| = 1;
select STDOUT;

my $cv = AE::cv;

$cv->begin;
for my $key (@line) {
  $cv->begin;
  my $page_name = $LinesData->{$key}->{wref} || $key;
  $mw->get_source_text_by_name_as_cv ($page_name, ims => ($force_update ? 0 : $Data->{$key} or {})->{timestamp} || 0)->cb (sub {
    my $data = $_[0]->recv;
    if (defined $data and defined $data->{data}) {
      my $doc = new Web::DOM::Document;
      my $parser = Text::MediaWiki::Parser->new;
      $parser->parse_char_string ($data->{data} => $doc);
      my $stations = extract_from_doc $page_name => $doc;
      $Data->{$key} = $LinesData->{$key};
      $Data->{$key}->{wref} = $page_name;
      $Data->{$key}->{names}->{$page_name} = 1;
      $Data->{$key}->{timestamp} = $data->{timestamp};
      $Data->{$key}->{stations} = $stations;
      print STDERR ".";
    } elsif ($data->{not_modified}) {
      #
    } else {
      warn "No data: |$page_name|\n";
    }
    $cv->end;
  });
}
$cv->end;

$cv->cb (sub {
  print STDERR " done\n";

  $Data->{東海道本線}->{stations} = [];

  print { $data_f->openw } perl2json_bytes_for_record $Data;
});

$cv->recv;

## See also:
##   Wikipedia:記事名の付け方/鉄道
##   <http://ja.wikipedia.org/wiki/Wikipedia:%E8%A8%98%E4%BA%8B%E5%90%8D%E3%81%AE%E4%BB%98%E3%81%91%E6%96%B9/%E9%89%84%E9%81%93>
