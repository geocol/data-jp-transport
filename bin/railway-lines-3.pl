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
    next unless defined $id;
    $Data->{lines}->{$id}->{names}->{$name} = 1;
    $Data->{lines}->{$id}->{wref} = $name if $line_ids->{$name}->{wref};
}

{
    my $f = file (__FILE__)->dir->parent->file ('src', 'railway-lines-names.txt');
    for (($f->slurp)) {
        my $line = decode 'utf-8', $_;
        if ($line =~ /^\s*#/) {
            #
        } elsif ($line =~ /^(\d+)\s+wref=(.+)$/) {
            $Data->{lines}->{$1}->{names}->{$2} = 1;
            $Data->{lines}->{$1}->{wref} = $2;
            $line_ids->{$2}->{id} ||= $1;
        } elsif ($line =~ /^(\d+)\s+(.+)$/) {
            $Data->{lines}->{$1}->{names}->{$2} = 1;
            $line_ids->{$2}->{id} ||= $1;
        } elsif ($line =~ /\S/) {
            die "Broken line: |$line|";
        }
    }
}

#my $lines = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'wp-railway-line-list.json');
my $lines = file2perl file (__FILE__)->dir->parent->file ('data', 'railway-lines.json');

for my $wref (keys %$lines) {
    my $id = ($line_ids->{$wref} or {})->{id};
    unless (defined $id) {
        push @{$Data->{_errors} ||= []}, "ID for line |$wref| not defined";
        next;
    }
    my $data = $lines->{$wref};
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
