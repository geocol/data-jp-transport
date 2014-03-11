use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);

my $root_d = file (__FILE__)->dir->parent;

my $Data = {};

my $ids = (file2perl $root_d->file ('intermediate', 'station-ids.json'))->{stations};
my $company_ids = (file2perl $root_d->file ('intermediate', 'company-ids.json'))->{companies};
my $line_ids = (file2perl $root_d->file ('intermediate', 'line-ids.json'))->{lines};
#my $stations = file2perl $root_d->file ('intermediate', 'wp-railway-stations.json');
my $stations = file2perl $root_d->file ('data', 'stations.json'); # XXX

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
        my $id = $line_ids->{$wref}->{id};
        if (defined $id) {
            $dest_data->{lines}->{$id} = $src_data->{lines}->{$wref};
        } else {
            push @{$Data->{_errors} ||= []}, "Line |$wref| has no ID";
        }
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
    if (defined $dest_data->{wref}) {
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
    for (values %{$src_data->{stations} or {}}) {
        my $companies = [sort { $a <=> $b } map { $company_ids->{$_}->{id} || '???' } keys %{$_->{company_wrefs} or {}}];
        my $id = $ids->{$wref, @$companies}->{id};
        unless (defined $id) {
            push @{$Data->{_errors} ||= []}, "Station |$wref @$companies| has no ID";
            next;
        }
        my $src_data = $_;
        my $dest_data = $Data->{stations}->{$id} ||= {};
        $dest_data->{parent_station} = $parent_id;
        $children->{$id} = 1;
        process_station $src_data => $dest_data;

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

print perl2json_bytes_for_record $Data;
