#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use HTML::TokeParser;

my $info = parse_doc(
  do { local $/; <> }
);
print service_cat( $info );

sub tidy($) {
  my $s = shift;
  for ( $s ) { s/^\s+//; s/\s+$//; s/\s+/ /g }
  return $s;
}

sub service_cat {
  my $svccat   = $_[0]->{svccat};
  my @svcnames = @{ $_[0]->{svcnames} };
  my %is_field = map { $_ => 1 } qw( userid publickey last );
  my %meth     = ();
  for my $svc ( @svcnames ) {
    ( my $func = $svc ) =~ s{\W+}{_}g;
    my ( $service, $action ) = split qr{/}, $svc;
    my @req = sort keys %{ $svccat->{$svc}{required} };
    my @opt = sort keys %{ $svccat->{$svc}{optional} };
    my @fld = grep { $is_field{$_} } @req;
    my @arg = grep { !$is_field{$_} } @req;
    $meth{$func} = {
      service => $service,
      action  => $action,
      ( @fld ? ( fields   => \@fld ) : () ),
      ( @opt ? ( optional => \@opt ) : () ),
      ( @arg ? ( required => \@arg ) : () ),
    };
  }
  return Data::Dumper->new( [ \%meth ] )->Indent( 2 )->Quotekeys( 0 )
   ->Useqq( 0 )->Terse( 1 )->Dump;
}

sub parse_doc {
  my $doc   = shift;
  my $p     = HTML::TokeParser->new( \$doc );
  my @path  = ();
  my @table = ();
  my $pp    = sub {
    return join '/', map { $_->[0] } @path;
  };
  my %struc = map { $_ => 1 } qw(
   div table td tr th h1 h2 h3 h4 h5 h6 h7 h8
  );
  my @context = ();
  my %rccat   = ();
  my %svccat  = ();
  my %tabledo = (
    defines => sub {
      #      print "Defines!\n";
      #      print Dumper( @_ );
    },
    parameters => sub {
      my $tt = shift;
      die "parameters outside context" unless @context;
      my @t = @{ $tt->{contents} };
      shift @t;
      my $last_req = undef;
      while ( my $row = shift @t ) {
        my ( $req, $name, $type, $desc ) = @$row;
        $req = $last_req if $req =~ /^\s*$/;
        $last_req = $req;
        $svccat{ $context[-1] }{$req}{$name}
         = { type => $type, desc => $desc };
      }
    },
    returncodes => sub {
      my $tt = shift;
      my @t  = @{ $tt->{contents} };
      shift @t;
      while ( my $row = shift @t ) {
        my ( $code, $message ) = @$row;
        $rccat{$code} = $message;
      }
    },
  );
  my %tagdo = (
    h2 => sub {
      return sub {
        my ( $tos, $text ) = @_;
        push @context, "$1/$2"
         if $text =~ m{^(\w+)\s*/\s*(\w+)$};
      };
    },
    table => sub {
      my ( undef, $attr ) = @_;
      push @table, { attr => $attr, contents => [] };
      return sub {
        my $tt = pop @table;
        ( $tabledo{ $tt->{attr}{class} || '' } || sub { } )->( $tt );
      };
    },
    tr => sub {
      push @{ $table[-1]{contents} }, [];
      return;
    },
    td => sub {
      return sub {
        push @{ $table[-1]{contents}[-1] }, $_[1];
      };
    },
    th => sub {
      return sub { $table[-1]{header} = $_[1] }
    },
  );
  my %tokdo = (
    S => [
      sub {
        my ( undef, $tag, $attr, $attrseq, $text ) = @_;
        push @path,
         [
          $tag, $attr,
          ( $tagdo{$tag} ||= sub { } )->( $tag, $attr ) || sub { }, [],
         ]
         if $struc{$tag};
       }
    ],
    E => [
      sub {
        my ( undef, $tag, $text ) = @_;
        if ( $struc{$tag} ) {
          my $tos = pop @path;
          die "Tag stack underflow" unless $tos;
          die "Mismatched closing tag, got $tag, expected $tos->[0]"
           unless $tag eq $tos->[0];
          $tos->[2]( $tos, tidy join ' ', @{ $tos->[3] } );
        }
       }
    ],
    T => [
      sub {
        my ( undef, $text, $is_data ) = @_;
        push @{ $path[-1][3] }, $text if @path;
       }
    ],
    C  => [ sub { } ],
    D  => [ sub { } ],
    PI => [ sub { } ],
  );
  while ( my $tok = $p->get_token ) {
    my $h = $tokdo{ $tok->[0] }[-1]
     or die "No handler for $tok->[0]";
    $h->( @$tok );
  }
  return {
    svcnames => \@context,
    rccat    => \%rccat,
    svccat   => \%svccat
  };
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

