use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $line = decode 'utf-8', shift;

my $list_f = $root_d->file ('intermediate', 'wp-railway-lines.json');
my $list = file2perl $list_f;
my $stations = [map { $_->{wref} // $_->{name} } @{$list->{$line}->{stations} or {}}];

my $i = 0;
{
  last if $i*100 > @$stations;
  warn sprintf "%d-%d of %d...\n", $i*100, ($i+1)*100-1, scalar @$stations;
  my @sub = grep { defined } @$stations[$i*100..($i+1)*100-1];
  if (@sub) {
    (system 'perl', $root_d->file ('bin', 'station.pl'), map { encode 'utf-8', $_ } @sub) == 0 or die $?;
    $i++;
    redo;
  }
}
