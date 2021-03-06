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
my $data_f = $root_d->file ('intermediate', 'wp-railway-stations.json');

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

my $IgnoredTemplates = {color => 1, flagicon => 1};

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
      } elsif ($ln eq 'include' and $IgnoredTemplates->{lc ($_->get_attribute ('wref') // '')}) {
        #
      } elsif ($ln eq 'include' and $_->get_attribute ('wref') eq '駅番号c') {
        my @ip = grep { $_->local_name eq 'iparam' } @{$_->children};
        if (defined $ip[1]) {
          $text .= _tc $ip[1];
        }
      } elsif ($ln eq 'include' and
               {駅番号s => 1,
                駅番号 => 1}->{$_->get_attribute ('wref')}) {
        my @ip = grep { $_->local_name eq 'iparam' } @{$_->children};
        if (defined $ip[2]) {
          $text .= _tc $ip[2];
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

sub _extract_objects ($$) {
  my ($el, $key) = @_;
  my @object;
  my $l;
  my @l;
  my @n;

  my $push_object = sub {
    my $v = _n join '', map { _tc $_ } @n;
    if ($v =~ /^\((?:いずれも|正式).+\)$/) {
      $v = '';
    }
    $v =~ s/\s*\*+\z//;
    for my $l (@l) {
      my $name = $l->get_attribute ('wref');
      my $orig_name = _tc $l;
      if (defined $name) {
        $name =~ s/\s+\z//;
      } else {
        $name = $orig_name;
        $name =~ s/\A\s+//;
        $name =~ s/\s*\*+\z//;
      }
      if ($v =~ s/\Q$orig_name\E((?:貨物|)支線)(?:[(（]([^()]+線)[)）])?//) {
        $name .= $1 . (defined $2 ? "($2)" : '');
      }
      if ($v =~ /\Q$orig_name\E[(（]((?!当駅より)[^()]*(?:支線|ライン)|分岐線|連絡線|BRT区間|[北南山海新旧]線)[)）]/) {
        $name .= $1;
        $v = '';
      }
      if ($v =~ /\Q$orig_name\E[(（]中央東線・本線[)）]/) {
        push @object, '中央東線', $name;
      } else {
        push @object, $name;
      }
    }
    if ($v =~ s/^.+線(?:貨物|)支線[(（](.+線)[)）]$//) {
      push @object, $1;
    }
    if ($v =~ s/^(.+線)[(（](貨物支線)[)）]$//) {
      push @object, "$1$2";
    }
    if ($v =~ s/^(三河線)[(（]通称([山海]線)[)）]$//) {
      push @object, "$1($2)";
    }
    if ($v =~ s/^(.+線)\s*\((?!(?:支|本|分岐|休止|[北南新旧]|後の.+|正式には.+)線\))([^()]+(?:線|ライン))\)$//) {
      push @object, map {
          s/^当駅(?:より|から).+(?:方|まで|側)は(?:愛称|)//;
          s/^旧名称・//; s/^通称//; $_;
      } grep { $_ ne '本線' and not $_ =~ /.+方快速線$/ and $_ ne '衣浦臨海鉄道、貨物線' and $_ ne '貨物専用線' } $1, split /(?<=線)[・]/, $2;
    }
    if ($v =~ s/^\((.+(?:線))\)$//) {
      my $w = $1;
      $w =~ s/^以上、//;
      $w =~ s/^通称(、|:|)//;
      $w =~ s/^当駅(?:より|から).+(?:方|まで|側)は(?:愛称|)//;
      $w =~ s/^所属路線は.+//;
      $w =~ s/^正式には.+//;
      $w =~ s/^線路名称上は.+//;
      push @object, grep { $_ ne '本線' } split /(?<=線)[・、]/, $w;
    }
    unless (@l) {
      if (length $v) {
        push @object, $v;
      }
    }
  }; # $push_object

  for (@{$el->child_nodes}) {
    if ($_->node_type == $_->ELEMENT_NODE) {
      my $ln = $_->local_name;
      if ($ln eq 'l') {
        if ($_->has_attribute ('embed')) {
          #
        } else {
          next if $_->text_content eq '駅詳細';
          $l //= $_;
          push @l, $_;
          push @n, $_;
        }
      } elsif ($ln eq 'comment' or $ln eq 'ref') {
        #
      } elsif ($ln eq 'include' and $IgnoredTemplates->{lc ($_->get_attribute ('wref') // '')}) {
        #
      } elsif ($ln eq 'span') {
        my $e = $_->query_selector ('l');
        if (defined $e) {
          if ($e->has_attribute ('embed')) {
            #
          } else {
            $l //= $e;
            push @l, $e;
            push @n, $_;
          }
        } else {
          push @n, $_ unless (_tc $_) eq "\x{25A0}";
        }
      } elsif ($ln eq 'br') {
        $push_object->();
        undef $l;
        @n = ();
      } else {
        push @n, $_;
      }
    } elsif ($_->node_type == $_->TEXT_NODE) {
      push @n, $_;
    }
  }

  $push_object->();

  if ($key eq 'line_wref') {
    @object = grep { not /駅(?:\s*\([^()]+\))?$/ and
                     not {東北本線別線 => 1,
                          東北本線電車線 => 1,
                          東北本線列車線 => 1,
                          東北本線貨物線 => 1,
                          東海道本線列車線 => 1,
                          東海道本線電車線 => 1,
                          東海道本線地下別線 => 1,
                          山手線電車線 => 1,
                          貨物線 => 1,
                          貨物支線 => 1,
                          '電車線・列車線' => 1,
                          電車線 => 1,
                          列車線 => 1}->{$_} } @object;
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
    objects => 1,
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
        $value = (_extract_objects $iparam, $fdef->{name})->[0];
      } elsif ($fdef->{objects}) {
        $value = _extract_objects $iparam, $fdef->{name};
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
        my %attr;
        my @ip;
        for (grep { $_->local_name eq 'iparam' } @{$el->children}) {
          my $name = $_->get_attribute ('name');
          if (defined $name) {
            $attr{$name} = _tc $_;
          } else {
            push @ip, _tc $_;
          }
        }
        if (defined $attr{format} and $attr{format} eq 'dms') {
          $data->{lat} = 0+$ip[0];
          $data->{lon} = 0+$ip[1];
        } else {
          $data->{lat} = ($ip[3] eq 'N' ? 1 : -1) * ($ip[0] + $ip[1] * (1/60) + $ip[2] * (1/3600));
          $data->{lon} = ($ip[7] eq 'E' ? 1 : -1) * ($ip[4] + $ip[5] * (1/60) + $ip[6] * (1/3600));
        }
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
  if (defined $props->{緯度秒} and length $props->{緯度秒}) {
    warn "Unsupported lat format - $data->{name}" if not defined $props->{緯度分};
    $data->{lat} = $props->{緯度度} + $props->{緯度分} * (1/60) + $props->{緯度秒} * (1/3600);
  }
  if (defined $props->{経度秒} and length $props->{経度秒}) {
    $data->{lon} = $props->{経度度} + $props->{経度分} * (1/60) + $props->{経度秒} * (1/3600);
  }
  if (defined $data->{company_wrefs} and
      ref $data->{company_wrefs} eq 'ARRAY') {
    $data->{company_wrefs} = {map { $_ => 1 } @{$data->{company_wrefs}}};
  }
  for (@$lines) {
    my $line_wrefs = delete $_->{line_wref} // '';
    for my $line_wref (@$line_wrefs) {
        $data->{lines}->{$line_wref} = $_;
    }
  }
  return $data;
} # parse_station

sub extract_station_as_cv ($) {
  my $wref = $_[0];
  $wref =~ s/#.+//s;
  $wref =~ tr/_/ /;
  my $cv = AE::cv;
  $cv->begin;
  $mw->get_source_text_by_name_as_cv ($wref, ims => $ENV{FORCE_UPDATE} ? 0 : ($Data->{$wref} or {})->{timestamp} || 0)->cb (sub {
    my $data = $_[0]->recv;
    if (defined $data and defined $data->{data}) {
      my $doc = new Web::DOM::Document;
      my $parser = Text::MediaWiki::Parser->new;
      $parser->parse_char_string ($data->{data} => $doc);
      my $stations = [@{$doc->query_selector_all ('include[wref="駅情報"]')}];
      if (@$stations) {
        my $station = shift @$stations;
        my $station_data = parse_station $station;
        $Data->{$wref} = $station_data;

        for (@$stations) {
          my $station_data = parse_station $_;
          unless (defined $station_data->{name}) {
              warn "No |name| - $wref";
              next;
          }
          $Data->{$wref}->{stations}->{$station_data->{name}} = $station_data;
        }

        $Data->{$wref}->{timestamp} = $data->{timestamp};
      }
    } elsif (defined $data and $data->{not_modified}) {
      #
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
  (($Data->{八丁畷駅} or {})->{lines}->{京急本線} or {})->{number} =~ s/\s*\(京急\)$//;
  $Data->{保土ヶ谷駅}->{stations}->{保土ヶ谷駅}->{lines}->{相模鉄道貨物支線} ||= {};
  delete $Data->{蟹田駅}->{lines}->{北海道旅客鉄道};
  print { $data_f->openw } perl2json_bytes_for_record $Data;
});

$cv->recv;
