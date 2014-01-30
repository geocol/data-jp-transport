use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $Lines = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'railway-stations.json');
my $Data = {};

for my $line (keys %$Lines) {
  for (@{$Lines->{$line}->{stations} or []}) {
    my $name = $_->{wref} || $_->{name};
    $Data->{$name}->{lines}->{$line} = 1;
  }
}

print perl2json_bytes_for_record $Data;
