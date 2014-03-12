use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use AnyEvent;
use AnyEvent::MediaWiki::Source;
use Text::MediaWiki::Parser;

my $cv = AE::cv;
$cv->begin;

my $root_d = file (__FILE__)->dir->parent;
my $mw = AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
    ($root_d->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml'),
     $root_d->subdir ('local', 'cache'));

my $Data = {};

for my $word (
  q(日本の鉄道路線一覧 あ-か行),
  q(日本の鉄道路線一覧 さ-な行),
  q(日本の鉄道路線一覧 は-わ行),
  q(日本の廃止鉄道路線一覧),
) {

$cv->begin;
$mw->get_source_text_by_name_as_cv ($word)->cb (sub {
  my $d = $_[0]->recv;
  if (defined $d) {
    my $doc = new Web::DOM::Document;
    my $parser = Text::MediaWiki::Parser->new;
    $parser->parse_char_string ($d => $doc);

    my $related = $doc->query_selector ('h1:-manakai-contains("関連項目")');
    if (defined $related) {
        $related->parent_node->parent_node->remove_child ($related->parent_node);
    }

    for my $l (@{$doc->query_selector_all ('section li > l:first-child')}) {
        my $name = $l->text_content;
        my $wref = $l->get_attribute ('wref') || $name;
        $Data->{$wref}->{closed} = 1 if $word =~ /廃止/ and not $Data->{$wref};
        $Data->{$wref}->{wref} = $wref;
        $Data->{$wref}->{names}->{$wref} = 1;
        $Data->{$wref}->{names}->{$name} = 1;
    }

    $cv->end;
  } else {
    die "Page not found\n";
  }
});

}

$cv->end;
$cv->recv;

for (qw(加悦鉄道 北丹鉄道 北見鉄道 南部鉄道 池田鉄道 沙流鉄道
        洞爺湖電気鉄道 津軽鉄道 渡島海岸鉄道 熊延鉄道 留萠鉄道
        雄別鉄道)) {
    if ($Data->{$_} and not $Data->{$_ . '線'}) {
        $Data->{$_}->{names}->{$_ . '線'} = 1;
    }
    if ($Data->{$_.'線'} and not $Data->{$_ . $_ . '線'}) {
        $Data->{$_.'線'}->{names}->{$_ . $_ . '線'} = 1;
    }
}

unless ($Data->{"尺別鉄道線"} or $Data->{"尺別鉄道"}) {
    $Data->{"雄別鉄道#尺別鉄道線"}->{names}->{"雄別鉄道#尺別鉄道線"} = 1;
    $Data->{"雄別鉄道#尺別鉄道線"}->{names}->{"尺別鉄道線"} = 1;
    $Data->{"雄別鉄道#尺別鉄道線"}->{names}->{"尺別鉄道"} = 1;
}

unless ($Data->{早来鉄道} or $Data->{早来鉄道線}) {
    $Data->{"あつまバス"}->{names}->{早来鉄道} = 1;
    $Data->{"あつまバス"}->{names}->{早来鉄道線} = 1;
}

unless ($Data->{宮島連絡船}) {
    $Data->{宮島連絡船}->{names}->{宮島連絡船} = 1;
}

use JSON::Functions::XS qw(perl2json_bytes_for_record);
print perl2json_bytes_for_record $Data;
