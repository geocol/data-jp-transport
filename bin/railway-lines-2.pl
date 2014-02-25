use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $Data = file2perl $root_d->file ('intermediate', 'railway-stations.json');

my $stations = file2perl $root_d->file ('intermediate', 'stations.json');

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

## <http://ja.wikipedia.org/wiki/JR%E6%9D%B1%E8%A5%BF%E7%B7%9A>
$Data->{JR東西線}->{company_wrefs}->{関西高速鉄道} = 1;

print perl2json_bytes_for_record $Data;
