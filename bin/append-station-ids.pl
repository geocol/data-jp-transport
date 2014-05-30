use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use JSON::Functions::XS qw(perl2json_bytes_for_record file2perl);

my $stations = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'wp-railway-stations.json');

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'station-ids.json');
my $Data = file2perl $data_f;
delete $Data->{_errors};

my $company_ids = (file2perl file (__FILE__)->dir->parent->file ('intermediate', 'company-ids.json'))->{companies};

my $next_id = 1;
for (values %{$Data->{stations}}) {
    if (defined $_->{id}) {
        $next_id = $_->{id} + 1 if $_->{id} >= $next_id;
    }
}
for (values %{$Data->{stations}}) {
    $_->{id} = $next_id++ unless defined $_->{id};
}

for my $wref (keys %$stations) {
    my $id = $Data->{stations}->{$wref} ? $Data->{stations}->{$wref}->{id} : $next_id++;
    $Data->{stations}->{$wref}->{id} = $id;

    for (values %{$stations->{$wref}->{stations} or {}}) {
        my @id;
        for (keys %{$_->{company_wrefs} or {}}) {
            my $id = $company_ids->{$_} ? $company_ids->{$_}->{id} : undef;
            if (defined $id) {
                push @id, $id;
            } else {
                push @{$Data->{_errors} ||= []}, "ID for company |$_| not defined";
            }
        }
        @id = sort { $a <=> $b } @id;
        my @suffix;
        if ($_->{name} eq $stations->{$wref}->{name} or
            $_->{name} =~ /\x20\Q$stations->{$wref}->{name}\E$/) {
            #
        } else {
            push @suffix, $_->{name};
        }
        if (@id) {
            my $id = $Data->{stations}->{$wref, @id, @suffix}
                ? $Data->{stations}->{$wref, @id, @suffix}->{id} : $next_id++;
            $Data->{stations}->{$wref, @id. @suffix}->{id} = $id;
            $Data->{stations}->{$wref, $_, @suffix}->{id} ||= $id for @id;
        } else {
            push @{$Data->{_errors} ||= []}, "|$wref|'s substation has no company";
        }
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
