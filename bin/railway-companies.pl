use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $Data = {};

my $company_ids = (file2perl $root_d->file ('intermediate', 'company-ids.json'))->{companies};

for my $name (keys %$company_ids) {
    my $id = $company_ids->{$name}->{id};
    $Data->{companies}->{$id}->{names}->{$name} = 1;
    if ($company_ids->{$name}->{wref}) {
        if (defined $Data->{companies}->{$id}->{wref} and
            not $Data->{companies}->{$id}->{wref} eq $name) {
            warn "Conflict wref: |$name| vs |$Data->{companies}->{$id}->{wref}|";
        } else {
            $Data->{companies}->{$id}->{wref} = $name;
        }
    }
}

{
    my $f = file (__FILE__)->dir->parent->file ('src', 'railway-companies-names.txt');
    for (($f->slurp)) {
        my $line = decode 'utf-8', $_;
        if ($line =~ /^\s*#/) {
            #
        } elsif ($line =~ /^(\d+)\s+wref=(.+)$/) {
            $Data->{companies}->{$1}->{names}->{$2} = 1;
            $Data->{companies}->{$1}->{wref} = $2;
        } elsif ($line =~ /^(\d+)\s+(.+)$/) {
            $Data->{companies}->{$1}->{names}->{$2} = 1;
        } elsif ($line =~ /\S/) {
            die "Broken line: |$line|";
        }
    }
}

print perl2json_bytes_for_record $Data;
