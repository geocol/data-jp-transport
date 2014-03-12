use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $line_ids = (file2perl $root_d->file ('intermediate', 'line-ids.json'))->{lines};
my $company_ids = (file2perl $root_d->file ('intermediate', 'company-ids.json'))->{companies};

my $Data = file2perl $root_d->file ('local', 'src-railway-lines.json');

{
  my $f = $root_d->file ('intermediate', 'wp-railway-line-list.json');
  my $json = file2perl $f;
  for my $wref (keys %$json) {
    my $id = $line_ids->{$wref}->{id};
    unless (defined $id) {
      push @{$Data->{_errors} ||= []}, "ID for line |$wref| not defined";
      next;
    }
    $Data->{lines}->{$id}->{wref} = $json->{$wref}->{wref}
        if defined $json->{$wref}->{wref};
    $Data->{lines}->{$id}->{closed} = 1 if $json->{$wref}->{closed};
    for (keys %{$json->{$wref}->{names} or {}}) {
        $Data->{lines}->{$id}->{names}->{$_} = 1;
    }
  }
}

{
  my $f = $root_d->file ('data', 'railway-lines.json'); # XXX
  my $json = file2perl $f;
  for my $wref (keys %$json) {
    my $id = $line_ids->{$wref}->{id};
    unless (defined $id) {
      push @{$Data->{_errors} ||= []}, "ID for line |$wref| not defined";
      next;
    }
    for (qw(shinkansen bus tram subway jr cablecar agt hsst
            monorail freight ferry)) {
      $Data->{lines}->{$id}->{$_} = $json->{$wref}->{$_}
          if defined $json->{$wref}->{$_};
    }
    $Data->{lines}->{$id}->{closed} = 1 if $json->{$wref}->{closed};

    for (keys %{$json->{$wref}->{company_wrefs}}) {
      if ($company_ids->{$_}) {
          $Data->{lines}->{$id}->{companies}->{$company_ids->{$_}->{id}} = 1;
      } else {
        push @{$Data->{_errors}}, "Company |$_| has no ID";
      }
    }
  }
}

print perl2json_bytes_for_record $Data;
