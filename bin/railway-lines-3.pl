use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $Data = {};

my $line_ids = (file2perl $root_d->file ('intermediate', 'line-ids.json'))->{lines};
my $company_ids = (file2perl $root_d->file ('intermediate', 'company-ids.json'))->{companies};

for my $name (keys %$line_ids) {
    my $id = $line_ids->{$name}->{id};
    $Data->{lines}->{$id}->{names}->{$name} = 1;
    $Data->{lines}->{$id}->{wref} = $name if $line_ids->{$name}->{wref};
}

my $lines = file2perl file (__FILE__)->dir->parent->file ('data', 'wp-railway-line-list.json');

for my $wref (keys %$lines) {
    my $id = ($line_ids->{$wref} or {})->{id};
    unless (defined $id) {
        warn "ID for line |$wref| not defined";
        next;
    }
    my $data = $lines->{$wref};
    if (defined $data->{wref} and
        defined $Data->{lines}->{$id}->{wref} and
        not $data->{wref} eq $Data->{lines}->{$id}->{wref}) {
        warn "Conflict #$id - |$data->{wref}| and |$Data->{lines}->{$id}->{wref}|";
    }
    if (defined $data->{wref} and not $data->{wref} eq $wref) {
        warn "Conflict #$id - |$data->{wref}| and |$wref|";
    }
    for my $k (keys %$data) {
        my $v = $data->{$k};
        if (ref $v eq 'HASH') {
            $Data->{lines}->{$id}->{$k}->{$_} = $v->{$_} for keys %$v;
        } else {
            $Data->{lines}->{$id}->{$k} ||= $v;
        }
    }
    for (keys %{$Data->{lines}->{$id}->{company_wrefs}}) {
        if ($company_ids->{$_}) {
            $Data->{lines}->{$id}->{companies}->{$company_ids->{$_}->{id}} = 1;
        } else {
            push @{$Data->{_errors}}, "Company |$_| has no ID";
        }
    }
    delete $Data->{lines}->{$id}->{company_wrefs};
    delete $Data->{lines}->{$id}->{stations}; # XXX
    delete $Data->{lines}->{$id}->{timestamp};
}

print perl2json_bytes_for_record $Data;
