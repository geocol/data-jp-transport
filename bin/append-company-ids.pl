use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use JSON::Functions::XS qw(perl2json_bytes_for_record file2perl);

my $stations = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'wp-railway-stations.json');

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'company-ids.json');
my $Data = file2perl $data_f;
delete $Data->{_errors};

my $next_id = 1;
for (values %{$Data->{companies}}) {
    next unless defined $_->{id};
    $next_id = $_->{id} + 1 if $_->{id} > $next_id;
}
for (values %{$Data->{companies}}) {
    $_->{id} = $next_id++ unless defined $_->{id};
}

for (keys %$stations) {
    for (keys %{$stations->{$_}->{company_wrefs}}) {
        if (/^#/) {
            push @{$Data->{_errors} ||= []}, "Broken wref: |$_|";
            next;
        }
        my $id = $Data->{companies}->{$_} ? $Data->{companies}->{$_}->{id} : $next_id++;
        $Data->{companies}->{$_}->{id} = $id;
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
