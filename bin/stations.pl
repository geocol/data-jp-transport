use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $f = $root_d->file ('intermediate', 'wp-stations.json');
my $Data = file2perl $f;

for (keys %$Data) {
    delete $Data->{timestamp};
}

{
    my $patterns_f = $root_d->file ('local/suffix-patterns.json');
    my $patterns = (file2perl $patterns_f)->{patterns};
    my $pattern = join '|', values %$patterns;

    my $regions_f = $root_d->file ('local/regions.json');
    my $regions = file2perl $regions_f;
    $regions = {%$regions, map { %{$regions->{$_}->{areas} or {}} } keys %$regions};

    sub addr_to_code ($) {
        my $addr = $_[0];
        my $data = [];
        $addr =~ s/^北海道[^郡]+郡/北海道/;
        while ($addr =~ s/^($pattern|[^都道府県市郡区町村]+[都道府県市郡区町村])//o) {
            push @$data, $1;
        }
        push @$data, $addr if length $addr;

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
        
        return $code; # or undef
    } # addr_to_code

    for my $station (keys %$Data) {
        if (defined $Data->{$station}->{location}) {
            my $code = addr_to_code $Data->{$station}->{location};
            $Data->{$station}->{location_code} = $code if defined $code;
        }
        for (values %{$Data->{$station}->{stations} or {}}) {
            if (defined $_->{location}) {
                my $code = addr_to_code $_->{location};
                $_->{location_code} = $code if defined $code;
            }
        }
    }
}

print perl2json_bytes_for_record $Data;
