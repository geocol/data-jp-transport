use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $f = $root_d->file ('local', 'station-locations.json');
my $json = file2perl $f;

my $patterns_f = $root_d->file ('local/suffix-patterns.json');
my $patterns = (file2perl $patterns_f)->{patterns};
my $pattern = join '|', values %$patterns;

my $regions_f = $root_d->file ('local/regions.json');
my $regions = file2perl $regions_f;
$regions = {%$regions, map { %{$regions->{$_}->{areas} or {}} } keys %$regions};

for my $area (keys %{$regions->{北海道}->{areas}}) {
  if ($area =~ /^上川郡/) {
    $regions->{北海道}->{areas}->{上川郡}->{areas}->{$_}
        = $regions->{北海道}->{areas}->{$area}->{areas}->{$_}
            for keys %{$regions->{北海道}->{areas}->{$area}->{areas}};
  } elsif ($area =~ /^中川郡/) {
      $regions->{北海道}->{areas}->{中川郡}->{areas}->{$_}
          = $regions->{北海道}->{areas}->{$area}->{areas}->{$_}
              for keys %{$regions->{北海道}->{areas}->{$area}->{areas}};
  }
}

sub w ($$) {
  my ($code, $data) = @_;
  print "$code\t";
  print encode 'utf-8', join ' / ', @$data;
  print "\n";
} # w

for (@$json) {
  my $addr = $_->[1];
  my $data = [];
  while ($addr =~ s/^($pattern|[^都道府県市郡区町村]+[都道府県市郡区町村])//o) {
    push @$data, $1;
  }
  push @$data, $addr if length;

  my $code;
  if (@$data >= 1 and $regions->{$data->[0]}) {
    $code = $regions->{$data->[0]}->{code};
    if (@$data >= 2 and $regions->{$data->[0]}->{areas}->{$data->[1]}) {
        $code = $regions->{$data->[0]}->{areas}->{$data->[1]}->{code} || $code;
      if (@$data >= 3 and $regions->{$data->[0]}->{areas}->{$data->[1]}->{areas}->{$data->[2]}) {
        $code = $regions->{$data->[0]}->{areas}->{$data->[1]}->{areas}->{$data->[2]}->{code} || $code;
      }
    }
  }

  #w $code, $data;

  $_->[2] = $code if defined $code;
}

print perl2json_bytes_for_record $json;
