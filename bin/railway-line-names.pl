use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $lines = {};

{
    my $json = file2perl $root_d->file ('local', 'src-railway-lines.json');
    for (keys %{$json->{lines}}) {
        for (keys %{$json->{lines}->{$_}->{names} or {}}) {
            $lines->{$_} = 1;
        }
    }
}

{
    my $json = file2perl $root_d->file ('intermediate', 'wp-railway-line-list.json');
    for my $wref (keys %$json) {
        $lines->{$wref} = 1;
        $lines->{$_} = 1 for keys %{$json->{$wref}->{names} or {}};
    }
}

{
    my $json = file2perl $root_d->file ('intermediate', 'wp-railway-stations.json');
    for my $wref (keys %$json) {
        for (keys %{$json->{$wref}->{lines} or {}}) {
            $lines->{$_} = 1;
        }
        for (values %{$json->{$wref}->{stations} or {}}) {
            for (keys %{$_->{lines} or {}}) {
                $lines->{$_} = 1;
            }
        }
    }
}

print encode 'utf-8', join "\x0A", sort { $a cmp $b } keys %$lines;
