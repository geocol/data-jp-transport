use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;
my $Data = {};

{
  my $f = $root_d->file ('src', 'railway-stations.txt');
  my $last_id;
  for (split /\x0D?\x0A/, decode 'utf-8', scalar $f->slurp) {
    if (/^\s*#/) {
      #
    } elsif (defined $last_id and /^  (\S+)\s+<-\s+(\S+)\s*<-$/) {
      $Data->{stations}->{$last_id}->{$1}->{$2} ||= {};
    } elsif (defined $last_id and /^  (\S+)\s+<-\s+(.+)$/) {
      $Data->{stations}->{$last_id}->{$1}->{$2} = 1;
    } elsif (defined $last_id and /^  (\S+)\s+=\s+(.+)$/) {
      $Data->{stations}->{$last_id}->{$1} = $2;
    } elsif (/^([0-9]+)$/) {
      $last_id = $1;
    } elsif (/\S/) {
      die "Broken line: |$_|";
    }
  }
}

print perl2json_bytes_for_record $Data;
