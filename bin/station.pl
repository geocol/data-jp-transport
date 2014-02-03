use strict;
use warnings;
use utf8;
use Path::Class;
use lib glob file (__FILE__)->dir->subdir ('modules', '*', 'lib')->stringify;
use Encode;
use AnyEvent;
use AnyEvent::MediaWiki::Source;
use Web::DOM::Document;
use Web::HTML::Table;
use Text::MediaWiki::Parser;
use JSON::Functions::XS qw(file2perl perl2json_bytes_for_record);
use Char::Normalize::FullwidthHalfwidth qw(get_fwhw_normalized);

my $root_d = file (__FILE__)->dir->parent;
my $data_f = $root_d->file ('data', 'stations.json');

my $Data = file2perl $data_f;

my $mw = AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
    ($root_d->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml'),
     $root_d->subdir ('local', 'cache'));

sub _n ($) {
  my $s = shift;
  $s =~ s/\A\s+//;
  $s =~ s/\s+\z//;
  $s =~ s/\s+/ /;
  return get_fwhw_normalized $s;
} # _n

sub _tc ($);
sub _tc ($) {
  my $el = $_[0];
  return $el->data unless $el->node_type == $el->ELEMENT_NODE;
  my $text = '';
  for (@{$el->child_nodes}) {
    if ($_->node_type == $_->ELEMENT_NODE) {
      my $ln = $_->local_name;
      if ($ln eq 'comment' or $ln eq 'ref') {
        #
      } elsif ($ln eq 'include' and $_->get_attribute ('wref') eq 'Color') {
        #
      } elsif ($ln eq 'include' and $_->get_attribute ('wref') eq '駅番号c') {
        my @ip = grep { $_->local_name eq 'iparam' } @{$_->children};
        if (defined $ip[1]) {
          $text .= _tc $ip[1];
        }
      } elsif ($ln eq 'span') {
        my $v = _tc $_;
        $text .= $text unless $text eq "\x{25A0}";
      } elsif ($ln eq 'br') {
        $text .= "\x0A";
      } else {
        $text .= _tc $_;
      }
    } elsif ($_->node_type == $_->TEXT_NODE) {
      $text .= $_->data;
    }
  }
  return $text;
} # _tc

sub _extract_objects ($) {
  my $el = shift;
  my @object;
  my $l;
  my @n;
  for (@{$el->child_nodes}) {
    if ($_->node_type == $_->ELEMENT_NODE) {
      my $ln = $_->local_name;
      if ($ln eq 'l' and not $_->has_attribute ('embed')) {
        $l //= $_;
      } elsif ($ln eq 'comment' or $ln eq 'ref') {
        #
      } elsif ($ln eq 'include' and $_->get_attribute ('wref') eq 'Color') {
        #
      } elsif ($ln eq 'span') {
        push @n, $_ unless (_tc $_) eq "\x{25A0}";
      } elsif ($ln eq 'br') {
        if (defined $l) {
          my $name = $l->get_attribute ('wref');
          if (defined $name) {
            push @object, $name;
          } else {
            push @object, _tc $l;
          }
        } else {
          my $v = _n join '', map { _tc $_ } @n;
          push @object, $v if length $v;
        }
        undef $l;
        @n = ();
      } else {
        push @n, $_;
      }
    } elsif ($_->node_type == $_->TEXT_NODE) {
      push @n, $_;
    }
  }

  if (defined $l) {
    my $name = $l->get_attribute ('wref');
    if (defined $name) {
      push @object, $name;
    } else {
      push @object, _tc $l;
    }
  } else {
    my $v = _n join '', map { _tc $_ } @n;
    push @object, $v if length $v;
  }

  return \@object;
} # _extract_objects

my $Fields = {
  駅名 => {
    name => 'name',
  },
  画像 => {
    name => 'photo_wref',
  },
  画像説明 => {
    name => 'photo_desc',
  },
  よみがな => {
    name => 'name_kana',
  },
  ローマ字 => {
    name => 'name_latin',
  },
  所在地 => {
    name => 'location',
    drop_after_newline => 1,
  },
  所属事業者 => {
    name => 'company_wrefs',
    objects => 1,
  },
  所属路線 => {
    name => 'line_wref',
    object => 1,
    line_indexed => 1,
  },
  駅番号 => {
    name => 'number',
    line_indexed => 1,
  },
};

sub parse_station ($) {
  my $station = shift;
  my $data = {};
  my $props = {};
  my $lines = [];
  for my $iparam (@{$station->query_selector_all ('iparam')}) {
    my $name = $iparam->get_attribute ('name') // next;
    my $name_stem = $name;
    $name_stem =~ s/\d+$//;
    my $fdef = $Fields->{$name} || $Fields->{$name_stem};
    if (defined $fdef->{name}) {
      my $value;
      if ($fdef->{object}) {
        $value = (_extract_objects $iparam)->[0];
      } elsif ($fdef->{objects}) {
        $value = _extract_objects $iparam;
      } elsif ($name =~ /_wref$/) {
        $value = _tc $iparam;
      } else {
        $value = _tc $iparam;
        if ($fdef->{drop_after_newline}) {
          $value =~ s/\x0A.*//s;
        }
        $value = _n $value;
        $value =~ s/\s*\*+$//;
      }
      if (defined $value and length $value) {
        if ($fdef->{line_indexed}) {
          my $index = 0;
          $index = $1 - 1 if $name =~ /(\d+)$/;
          $lines->[$index]->{$fdef->{name}} = $value;
        } else {
          $data->{$fdef->{name}} = $value;
        }
      }
    } elsif ($name eq '座標') {
      my $el;
      for (@{$iparam->children}) {
        if ($_->local_name eq 'include' and
            {ウィキ座標2段度分秒 => 1,
             ウィキ座標度分秒 => 1,
             coord => 1}->{$_->get_attribute ('wref')}) {
          $el = $_;
          last;
        }
      }
      if (defined $el) {
        my @ip = map { _tc $_ } grep { $_->local_name eq 'iparam' } @{$el->children};
        $data->{lat} = ($ip[3] eq 'N' ? 1 : -1) * ($ip[0] + $ip[1] * (1/60) + $ip[2] * (1/3600));
        $data->{lon} = ($ip[7] eq 'E' ? 1 : -1) * ($ip[4] + $ip[5] * (1/60) + $ip[6] * (1/3600));
      }
    } elsif ({qw(緯度度 1 緯度分 1 緯度秒 1
                 経度度 1 経度分 1 経度秒 1)}->{$name}) {
      $props->{$name} = _n _tc $iparam
    } elsif ($name eq '開業年月日') {
      my $value = _n _tc $iparam;
      if ($value =~ /(\d+)年\s*\([^()]+\)\s*(\d+)月(\d+)日/) {
        $data->{open_date} = sprintf '%04d-%02d-%02d', $1, $2, $3;
      }
    } elsif ($name eq '廃止年月日') {
      my $value = _n _tc $iparam;
      if ($value =~ /(\d+)年\s*\([^()]+\)\s*(\d+)月(\d+)日/) {
        $data->{closed_date} = sprintf '%04d-%02d-%02d', $1, $2, $3;
      }
    }
  } # $iparam
  if (defined $props->{緯度秒}) {
    $data->{lat} = $props->{緯度度} + $props->{緯度分} * (1/60) + $props->{緯度秒} * (1/3600);
  }
  if (defined $props->{経度秒}) {
    $data->{lon} = $props->{経度度} + $props->{経度分} * (1/60) + $props->{経度秒} * (1/3600);
  }
  for (@$lines) {
    my $line_wref = delete $_->{line_wref} // '';
    $data->{lines}->{$line_wref} = $_;
  }
  return $data;
} # parse_station

sub extract_station_as_cv ($) {
  my $wref = $_[0];
  $wref =~ s/#.+//s;
  $wref =~ tr/_/ /;
  my $cv = AE::cv;
  $cv->begin;
  $mw->get_source_text_by_name_as_cv ($wref)->cb (sub {
    my $data = $_[0]->recv;
    if (defined $data) {
      my $doc = new Web::DOM::Document;
      my $parser = Text::MediaWiki::Parser->new;
      $parser->parse_char_string ($data => $doc);
      my $stations = [@{$doc->query_selector_all ('include[wref="駅情報"]')}];
      if (@$stations) {
        my $station = shift @$stations;
        my $data = parse_station $station;
        $Data->{$wref} = $data;

        for (@$stations) {
          my $data = parse_station $_;
          $Data->{$wref}->{stations}->{$data->{name}} = $data;
        }
      }
    } else {
      warn "No data: |$wref|\n";
    }
    $cv->end;
  });
  return $cv;
} # extract_station_as_cv

my $cv = AE::cv;
$cv->begin;
for (@ARGV) {
  $cv->begin;
  extract_station_as_cv (decode 'utf-8', $_)->cb (sub { $cv->end });
}
$cv->end;

$cv->cb (sub {
  print { $data_f->openw } perl2json_bytes_for_record $Data;
});

$cv->recv;
