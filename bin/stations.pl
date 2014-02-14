use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $f = $root_d->file ('intermediate', 'stations.json');
my $Data = file2perl $f;

for (keys %$Data) {
  delete $Data->{timestamp};
}

{
  my $f = $root_d->file ('local', 'station-location-regions.json');
  for (@{file2perl $f}) {
    $Data->{$_->[0]}->{location_code} = $_->[2]
        if defined $_->[2];
  }
}

print perl2json_bytes_for_record $Data;
