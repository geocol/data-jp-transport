use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $stations_f = file (__FILE__)->dir->parent->file ('data', 'stations.json');
my $stations = file2perl $stations_f;

my $Data = {};

for (keys %$stations) {
    my $data = $stations->{$_};
    next if $data->{closed_date};
    if ($data->{location_code}) {
        for (keys %{$data->{lines}}) {
            $Data->{substr $data->{location_code}, 0, 2}->{$_}++;
            $Data->{$data->{location_code}}->{$_}++;
        }
    }
    for my $station (values %{$data->{stations}}) {
        next if $station->{closed_date};
        next unless $station->{location_code};
        for (keys %{$station->{lines}}) {
            $Data->{substr $station->{location_code}, 0, 2}->{$_}++;
            $Data->{$station->{location_code}}->{$_}++;
        }
    }
}

print perl2json_bytes_for_record $Data;
