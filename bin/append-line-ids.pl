use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib');
use JSON::Functions::XS qw(perl2json_bytes_for_record file2perl);

my $lines = file2perl file (__FILE__)->dir->parent->file ('intermediate', 'railway-lines.json');

my $data_f = file (__FILE__)->dir->parent->file ('intermediate', 'line-ids.json');
my $Data = file2perl $data_f;

my $next_id = 1;
for (values %$Data) {
    next unless defined $_->{id};
    $next_id = $_->{id} + 1 if $_->{id} > $next_id;
}

for (keys %$lines) {
    my @name = keys %{$lines->{$_}->{names}};
    my $id = $Data->{$_} ? $Data->{$_}->{id} : $next_id++;
    for (@name) {
        if ($Data->{$_} and $Data->{$_}->{id} != $id) {
            $Data->{$_}->{conflicting_ids}->{$Data->{$_}->{id}} = 1;
            $Data->{$_}->{conflicting_ids}->{$id} = 1;
        } else {
            $Data->{$_}->{id} = $id;
        }
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
