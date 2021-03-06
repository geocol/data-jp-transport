use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $Data = file2perl $root_d->file ('local', 'src-railway-stations.json');

my $ids = (file2perl $root_d->file ('intermediate', 'station-ids.json'))->{stations};
my $company_ids = (file2perl $root_d->file ('intermediate', 'company-ids.json'))->{companies};
my $line_ids = (file2perl $root_d->file ('intermediate', 'line-ids.json'))->{lines};
my $stations = file2perl $root_d->file ('intermediate', 'wp-railway-stations.json');

sub process_station ($$) {
    my ($src_data => $dest_data) = @_;
    for (keys %$src_data) {
        next if $_ eq 'timestamp';
        next if $_ eq 'company_wrefs';
        next if $_ eq 'stations';
        next if $_ eq 'lines';
        $dest_data->{$_} = $src_data->{$_};
    }
    for my $wref (keys %{$src_data->{company_wrefs}}) {
        my $id = $company_ids->{$wref}->{id};
        if (defined $id) {
            $dest_data->{companies}->{$id} = 1;
        } else {
            push @{$Data->{_errors} ||= []}, "Company |$wref| has no ID";
        }
    }
    for my $wref (keys %{$src_data->{lines} or {}}) {
        my $line_def;
        for (keys %{$src_data->{company_wrefs}}) {
            $line_def ||= $line_ids->{$_ . $wref};
        }
        $line_def ||= $line_ids->{$wref};
        my $id = $line_def->{id};
        if (defined $id) {
            $dest_data->{lines}->{$id} = $src_data->{lines}->{$wref};
        } else {
            push @{$Data->{_errors} ||= []}, "Line |$wref| has no ID";
        }
    }

  if (defined $dest_data->{name}) {
    $dest_data->{name} =~ s/\(仮称\)$//;
    $dest_data->{name} =~ s/ステーション駅$/ステーション/;
    if ($dest_data->{name} =~ / /) {
      $dest_data->{label_qualified} = delete $dest_data->{name};
      $dest_data->{label} = [split / +/, $dest_data->{label_qualified}, 2]->[1];
    } else {
      $dest_data->{label} = delete $dest_data->{name};
    }
    $dest_data->{name} = $dest_data->{label};
    $dest_data->{name} =~ s/(?:駅|停留場|電停|停留所|信号場|仮乗降場|分岐点)$//;
  }
} # process_station

for my $wref (keys %$stations) {
    my $id = $ids->{$wref}->{id};
    unless (defined $id) {
        push @{$Data->{_errors} ||= []}, "Station |$wref| has no ID";
        next;
    }
    my $src_data = $stations->{$wref};
    my $dest_data = $Data->{stations}->{$id} ||= {};
    if (defined $dest_data->{wref} and not $dest_data->{wref} eq $wref) {
        push @{$Data->{_errors} ||= []}, "|wref| conflict - |$wref| vs |$dest_data->{wref}|";
        next;
    }
    $dest_data->{wref} = $wref;
    process_station $src_data => $dest_data;

    my $has_different_name;
    my $has_non_closed;
    my %company = %{$src_data->{company_wref} or {}};
    my $children = {};

    my $parent_id = $id;
    my $parent_dest_data = $dest_data;
    for (values %{$src_data->{stations} or {}}) {
        my $companies = [sort { $a <=> $b } map { $company_ids->{$_}->{id} || '???' } keys %{$_->{company_wrefs} or {}}];
        my @suffix;
        if ($_->{name} eq $stations->{$wref}->{name} or
            $_->{name} =~ /\x20\Q$stations->{$wref}->{name}\E$/) {
            #
        } else {
            push @suffix, $_->{name};
        }
        my $id = $ids->{$wref, @$companies. @suffix}->{id};
        unless (defined $id) {
            push @{$Data->{_errors} ||= []}, "Station |$wref @$companies @suffix| has no ID";
            next;
        }
        my $src_data = $_;
        my $dest_data = $Data->{stations}->{$id} ||= {};
        $dest_data->{parent_station} = $parent_id;
        $children->{$id} = 1;
        process_station $src_data => $dest_data;

        $dest_data->{lat} ||= $parent_dest_data->{lat}
            if defined $parent_dest_data->{lat};
        $dest_data->{lon} ||= $parent_dest_data->{lon}
            if defined $parent_dest_data->{lon};

        $has_different_name = 1 unless $_->{name} =~ /$wref/;
        delete $company{$_} for keys %{$_->{company_wrefs} or {}};
        $has_non_closed = 1 if not defined $src_data->{closed_date};
    }

    $dest_data->{child_stations} = $children if keys %$children;
    if (keys %{$src_data->{stations} or {}} and
        not keys %company and
        not $has_different_name and
        $has_non_closed) {
        $dest_data->{abstract} = 1;
    }
}

## 長木沢駅
delete $Data->{stations}->{2577}->{lines}->{558};

print perl2json_bytes_for_record $Data;
