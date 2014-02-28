use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use MediaWikiXML::PageExtractor;

my $root_d = file (__FILE__)->dir->parent;
my $pattern = qr{鉄道路線一覧|線|駅|停留|電停|信号所};

my $dump_f = $root_d->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml');
my $cache_d = $root_d->subdir ('local', 'cache');

my $mx = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d);
$mx->save_titles_from_f_if_necessary ($dump_f);
$mx->save_page_xml_from_f ($dump_f, $pattern);
