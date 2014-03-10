use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $Data = {};

my $line_ids = file2perl $root_d->file ('intermediate', 'line-ids.json');

for my $name (keys %$line_ids) {
    my $id = $line_ids->{$name}->{id};
    $Data->{lines}->{$id}->{names}->{$name} = 1;
}

my $lines = file2perl file (__FILE__)->dir->parent->file ('data', 'railway-lines.json');

for my $wref (keys %$lines) {
    my $id = ($line_ids->{$wref} or {})->{id};
    unless (defined $id) {
        warn "ID for line |$wref| not defined";
        next;
    }
    my $data = $lines->{$wref};
    if (defined $data->{wref} and not $data->{wref} eq $wref) {
        warn "Conflict #$id - |$data->{wref}| and |$wref|";
    }
    for my $k (keys %$data) {
        my $v = $data->{$k};
        if (ref $v eq 'HASH') {
            $Data->{$id}->{$k}->{$_} = $v->{$_} for keys %$v;
        } else {
            $Data->{$id}->{$k} = $v;
        }
    }
    delete $Data->{$id}->{company_wrefs}; # XXX
    delete $Data->{$id}->{stations}; # XXX
    delete $Data->{$id}->{timestamp};
}

print perl2json_bytes_for_record $Data;
