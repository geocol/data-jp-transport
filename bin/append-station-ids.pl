use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use JSON::Functions::XS qw(perl2json_bytes_for_record file2perl);

my $stations = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'wp-railway-stations.json');

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'station-ids.json');
my $Data = file2perl $data_f;

my $company_ids = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'company-ids.json');

my $next_id = 1;
for (values %$Data) {
    if (defined $_->{id}) {
        $next_id = $_->{id} + 1 if $_->{id} > $next_id;
    }
}
for (values %$Data) {
    $_->{id} = $next_id++ unless defined $_->{id};
}

for my $wref (keys %$stations) {
    my $id = $Data->{$wref} ? $Data->{$wref}->{id} : $next_id++;
    $Data->{$wref}->{id} = $id;

    for (values %{$stations->{$wref}->{stations} or {}}) {
        my @id;
        for (keys %{$_->{company_wrefs} or {}}) {
            my $id = $company_ids->{$_} ? $company_ids->{$_}->{id} : undef;
            if (defined $id) {
                push @id, $id;
            } else {
                warn "ID for company |$_| not defined";
            }
        }
        @id = sort { $a <=> $b } @id;
        if (@id) {
            my $id = $Data->{$wref, @id} ? $Data->{$wref}->{id} : $next_id++;
            $Data->{$wref, @id}->{id} = $id;
        } else {
            warn "|$wref|'s substation has no company";
        }
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
