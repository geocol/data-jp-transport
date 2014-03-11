use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(json_bytes2perl);

my $root_d = file (__FILE__)->dir->parent;

local $/ = undef;
my $json = <>;
my $stations = json_bytes2perl $json;

my $i = 0;
{
  last if $i*100 > @$stations;
  warn sprintf "%d-%d of %d...\n", $i*100, ($i+1)*100-1, scalar @$stations;
  my @sub = grep { defined } @$stations[$i*100..($i+1)*100-1];
  if (@sub) {
    (system 'perl', $root_d->file ('bin', 'wp-railway-station-update-by-name.pl'), map { encode 'utf-8', $_ } @sub) == 0 or die $?;
    $i++;
    redo;
  }
}
