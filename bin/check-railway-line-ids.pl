use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $json = file2perl $root_d->file ('data', 'railways/lines.json');

my $Data = {};

for my $id (keys %{$json->{lines}}) {
    $Data->{lines}->{$json->{lines}->{$id}->{wref}}->{id} ||= 0+$id
        if defined $json->{lines}->{$id}->{wref};
    $Data->{lines}->{$_}->{id} = 0+$id for keys %{$json->{lines}->{$id}->{names} or {}};
}

my $out_f = $root_d->file ('local', 'railway-line-ids.json');
print { $out_f->openw } perl2json_bytes_for_record $Data;

my $orig_f = $root_d->file ('intermediate', 'line-ids.json');
my $diff_f = $root_d->file ('local', 'railway-line-ids.json.diff');
system "diff -u \Q$orig_f\E \Q$out_f\E > \Q$diff_f\E";
