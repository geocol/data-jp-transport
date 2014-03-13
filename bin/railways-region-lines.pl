use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $stations_f = file (__FILE__)->dir->parent->file ('data', 'railways', 'stations.json');
my $stations = file2perl $stations_f;

my $lines = file2perl file (__FILE__)->dir->parent->file ('data', 'railways', 'lines.json');

my $Data = {};

for (keys %{$stations->{stations}}) {
    my $data = $stations->{stations}->{$_};
    next if $data->{closed_date};
    if ($data->{location_code}) {
        for my $key (keys %{$data->{lines}}) {
            $Data->{substr $data->{location_code}, 0, 2}->{$key}++;
            $Data->{$data->{location_code}}->{$key}++;
        }
    }
}

print perl2json_bytes_for_record $Data;
