use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use JSON::Functions::XS qw(perl2json_bytes_for_record file2perl);

my $lines = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'wp-railway-line-list.json');

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'line-ids.json');
my $Data = file2perl $data_f;
delete $Data->{_errors};

my $next_id = 1;
for (values %{$Data->{lines}}) {
    if (defined $_->{id}) {
        $next_id = $_->{id} + 1 if $_->{id} > $next_id;
    }
}
for (values %{$Data->{lines}}) {
    $_->{id} = $next_id++ unless defined $_->{id};
}

for (keys %$lines) {
    my @name = keys %{$lines->{$_}->{names}};
    my $id = $Data->{lines}->{$_} ? $Data->{lines}->{$_}->{id} : $next_id++;
    for (@name) {
        if ($Data->{lines}->{$_} and $Data->{lines}->{$_}->{id} != $id) {
            $Data->{lines}->{$_}->{conflicting_ids}->{$Data->{lines}->{$_}->{id}} = 1;
            $Data->{lines}->{$_}->{conflicting_ids}->{$id} = 1;
        } else {
            $Data->{lines}->{$_}->{id} = $id;
        }
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
