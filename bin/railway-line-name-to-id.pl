use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $data_f = $root_d->file ('intermediate', 'line-ids.json');

my $Data = file2perl $data_f;
my $next_id = 1;
for (keys %{$Data->{lines}}) {
    my $id = $Data->{lines}->{$_}->{id} // next;
    if ($id >= $next_id) {
        $next_id = $id + 1;
    }
}
for (values %{$Data->{lines}}) {
    $_->{id} = $next_id++ unless defined $_->{id};
}

for (split /\x0D?\x0A/, decode 'utf-8', $root_d->file ('local', 'railway-line-names.txt')->slurp) {
    if (/^(.+)$/) {
        $Data->{lines}->{$1}->{id} ||= $next_id++;
    }
}

print { $data_f->openw } perl2json_bytes_for_record $Data;
