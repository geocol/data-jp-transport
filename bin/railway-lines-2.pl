use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $Data = {};

my $line_list = file2perl $root_d->file ('intermediate', 'wp-railway-line-list.json');
my $lines = file2perl $root_d->file ('intermediate', 'wp-railway-lines.json');
$Data = $line_list;
for (keys %$lines) {
    $Data->{$_}->{stations} = $lines->{$_}->{stations} if $lines->{$_}->{stations};
}

my $stations = file2perl $root_d->file ('intermediate', 'wp-railway-stations.json');

for (keys %$stations) {
    my $station = $stations->{$_};

    for (values %{$station->{stations}}) {
        for my $line (keys %{$_->{lines}}) {
            my $multi = 1 < keys %{$_->{company_wrefs}};
            my $closed = defined $_->{closed_date};
            for my $company (keys %{$_->{company_wrefs}}) {
                $Data->{$line}->{company_wrefs}->{$company}->{$multi ? 'multiple' : 'single', $closed ? 'closed' : ''}++;
            }
            $Data->{$line}->{names}->{$line} = 1;
            delete $station->{lines}->{$line};
        }
    }

    for my $line (keys %{$station->{lines}}) {
        my $multi = 1 < keys %{$station->{company_wrefs}};
        my $closed = defined $station->{closed_date};
        for my $company (keys %{$station->{company_wrefs}}) {
            $Data->{$line}->{company_wrefs}->{$company}->{$multi ? 'multiple' : 'single', $closed ? 'closed' : ''}++;
        }
        $Data->{$line}->{names}->{$line} = 1;
    }
}

## <http://ja.wikipedia.org/wiki/JR%E6%9D%B1%E8%A5%BF%E7%B7%9A>
$Data->{JR東西線}->{company_wrefs}->{関西高速鉄道}->{'single', ''} = 1
    if $Data->{JR東西線}->{company_wrefs}->{関西高速鉄道};

## <http://ja.wikipedia.org/wiki/%E5%A4%A7%E9%98%AA%E5%A4%96%E7%92%B0%E7%8A%B6%E9%89%84%E9%81%93>
$Data->{おおさか東線}->{company_wrefs}->{大阪外環状鉄道}->{'single', ''} = 1
    if $Data->{おおさか東線}->{company_wrefs}->{大阪外環状鉄道};

for my $line (keys %$Data) {
    my $companies = $Data->{$line}->{company_wrefs} or next;
    my $has_single;
    my $has_non_closed;
    for (values %$companies) {
        $has_single = 1 if $_->{'single', ''} or $_->{'single', 'closed'};
        $has_non_closed = 1 if $_->{'single', ''} or $_->{'multiple', ''};
    }
    my $new = $Data->{$line}->{company_wrefs} = {};
    for (keys %$companies) {
        $new->{$_} = 1 if $companies->{$_}->{$has_single ? 'single' : 'multiple', $has_non_closed ? '' : 'closed'};
    }
    if ($new->{日本貨物鉄道} and 1 < keys %$new) {
        delete $new->{日本貨物鉄道};
    }
    #$Data->{$line}->{_company_wrefs} = $companies;
    $Data->{$line}->{closed} = 1 unless $has_non_closed;
}

## <http://ja.wikipedia.org/wiki/%E4%BA%88%E5%9C%9F%E7%B7%9A>
delete $Data->{予土線}->{company_wrefs}->{土佐くろしお鉄道};

delete $Data->{能勢電鉄妙見線}->{company_wrefs}->{阪急電鉄};

delete $Data->{東海道本線}->{company_wrefs}->{日本国有鉄道};

## <http://ja.wikipedia.org/wiki/%E9%87%8E%E5%B2%A9%E9%89%84%E9%81%93%E4%BC%9A%E6%B4%A5%E9%AC%BC%E6%80%92%E5%B7%9D%E7%B7%9A>
delete $Data->{野岩鉄道会津鬼怒川線}->{company_wrefs}->{会津鉄道};
delete $Data->{野岩鉄道会津鬼怒川線}->{company_wrefs}->{東武鉄道};

for my $line (keys %$Data) {
    my $data = $Data->{$line};
    if ($data->{company_wrefs}->{北海道旅客鉄道} or
        $data->{company_wrefs}->{東日本旅客鉄道} or
        $data->{company_wrefs}->{東海旅客鉄道} or
        $data->{company_wrefs}->{西日本旅客鉄道} or
        $data->{company_wrefs}->{四国旅客鉄道} or
        $data->{company_wrefs}->{九州旅客鉄道} or
        $data->{company_wrefs}->{日本貨物鉄道} or
        $data->{company_wrefs}->{日本国有鉄道}) {
        $data->{jr} = 1;
    }

    ## <http://ja.wikipedia.org/wiki/%E6%96%B0%E5%B9%B9%E7%B7%9A>
    $data->{shinkansen} = 'full' if $line =~ /新幹線/;
    $data->{shinkansen} = 'mini' if $line =~ /秋田新幹線|山形新幹線/;
    $data->{shinkansen} = 'misc' if $line =~ /博多南線|ガーラ湯沢/;

    ## <http://ja.wikipedia.org/wiki/%E3%82%B1%E3%83%BC%E3%83%96%E3%83%AB%E3%82%AB%E3%83%BC>
    $data->{cablecar} = 1 if $line =~ /ケーブル|鋼索|竜飛斜坑線|比叡山鉄道/;

    ## <http://ja.wikipedia.org/wiki/%E3%83%88%E3%83%AD%E3%83%AA%E3%83%BC%E3%83%90%E3%82%B9>
    $data->{bus} = 'trolley' if $line =~ /無軌条|トロリー/;

    ## <http://ja.wikipedia.org/wiki/%E3%82%AC%E3%82%A4%E3%83%89%E3%82%A6%E3%82%A7%E3%82%A4%E3%83%90%E3%82%B9>
    $data->{bus} = 'guided' if $line =~ /ガイドウェイ/;

    $data->{bus} = 'brt' if $line =~ /BRT/;

    ## <http://ja.wikipedia.org/wiki/%E6%97%A5%E6%9C%AC%E3%81%AE%E8%B7%AF%E9%9D%A2%E9%9B%BB%E8%BB%8A%E4%B8%80%E8%A6%A7>
    $data->{tram} = 1 if $line =~ /札幌市電|函館市企業局|都電荒川線|東田本線|富山市内軌道|阪堺線|上町線|東山本線|清輝橋線|広島電鉄|土佐電気鉄道|伊予鉄道|長崎電気軌道|熊本市電|鹿児島市電/;
    $data->{tram} = 'partial' if $line =~ /東急世田谷線|ライトレール|万葉線|福武線|京津線|石山坂本線|嵐山本線|北野線/;
    delete $data->{tram} if $line =~ /万葉線新湊港線/;

    ## <http://ja.wikipedia.org/wiki/%E6%97%A5%E6%9C%AC%E3%81%AE%E5%9C%B0%E4%B8%8B%E9%89%84>
    $data->{subway} = 1 if $line =~ /地下鉄|メトロ|みなとみらい/;
    $data->{subway} = 'partial' if $line =~ /広島新交通1号線/;

    ## <http://ja.wikipedia.org/wiki/%E6%96%B0%E4%BA%A4%E9%80%9A%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0>
    $data->{agt} = 1 if $line =~ /埼玉新都市交通|東京臨海新交通臨海線|シーサイドライン|日暮里・舎人ライナー|西武山口線|ユーカリが丘線|南港ポートタウン線|神戸新交通|広島高速交通|桃花台新交通/;
    $data->{hsst} = 1 if $line =~ /東部丘陵線/;

    ## <http://ja.wikipedia.org/wiki/%E6%97%A5%E6%9C%AC%E3%81%AE%E3%83%A2%E3%83%8E%E3%83%AC%E3%83%BC%E3%83%AB>
    $data->{monorail} = 1 if $line =~ /モノレール|上野懸垂線|ディズニーリゾートライン|大阪高速鉄道|広島短距離交通瀬野線|北九州高速鉄道/;

    ## <http://ja.wikipedia.org/wiki/%E8%B2%A8%E7%89%A9%E7%B7%9A>
    $data->{freight} = 1 if $line =~ /貨物|三ヶ尻線/;
    $data->{freight} = 1 if $data->{company_wrefs}->{日本貨物鉄道} and
                            1 == keys %{$data->{company_wrefs}};

    $data->{ferry} = 1 if $line =~ /連絡船/;
}

print perl2json_bytes_for_record $Data;
