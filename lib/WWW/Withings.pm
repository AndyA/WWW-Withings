package WWW::Withings;

use warnings;
use strict;

use Carp;
use JSON;
use Data::Dumper;
use LWP::UserAgent;

=head1 NAME

WWW::Withings - Interface to Withings Wifi bathroom scales

=head1 VERSION

This document describes WWW::Withings version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

  use WWW::Withings;
  my $withings = WWW::Withings->new( userid => 'foo', publickey => 'xabc123' );
  
=head1 DESCRIPTION

=cut

#http://wbsapi.withings.net/[service_name]?action=[action_name]&[parameters]
use constant API => 'http://wbsapi.withings.net';

use accessors::ro qw( userid publickey last );

BEGIN {
  my %meth = (
    probe => {
      required => [qw( userid publickey )],
      optional => [],
      service  => 'once',
      action   => 'probe',
    },
    measure => {
      required => [qw( userid publickey )],
      optional => [
        qw( startdate enddate meastype lastupdate category limit offset )
      ],
      service => 'measure',
      action  => 'getmeas',
    },
  );
  my @APIARGS = qw( service action required optional );
  for my $m ( keys %meth ) {
    no strict 'refs';
    *{$m} = sub { shift->_api( @{ $meth{$m} }{@APIARGS}, @_ ) };
  }
}

sub _need {
  my ( $need, $optional, @args ) = @_;
  croak "Expected a number of key => value pairs"
   if @args % 2;
  my %args = @args;
  my @missing = grep { !defined $args{$_} } @$need;
  croak "Missing options: ", join( ', ', sort @missing )
   if @missing;
  if ( defined $optional ) {
    my %ok = map { $_ => 1 } @$need, @$optional;
    my @extra = grep { !$ok{$_} } keys %args;
    croak "Illegal otions: ", join( ', ', sort @extra ) if @extra;
  }
  return %args;
}

=head2 C<< new >>

Create a new C<WWW::Withings> object. In common with all methods exposed
by the module accepts a number of key => value pairs. The C<userid>
and C<publickey> options are mandatory:

  my $withings = WWW::Withings->new(
    userid    => 'alice',
    publickey => 'x3122b4c4d3bad5e8d7397f0501b617ce60afe5d'
  );

=cut

sub new {
  my $class = shift;
  return bless { _need( [ 'publickey', 'userid' ], [], @_ ) }, $class;
}

=head2 API Calls

API calls provide access to the Withings API.

On success they return a reference to a hash containing the response
from withings.com. On errors an exception will be thrown. In the case of
an error the response hash can be retrieved by calling C<last>.

=head3 C<< api >>

API entry points other than C<subscribe_user> and C<send_notification>
(of which there are currently none) can be accessed directly by calling
C<api>. For example, the above send_notification example can also be
written as:

  my $resp = $withings->api(
    'send_notification',
    to    => 'hexten',
    msg   => 'Testing...',
    label => 'Test',
    title => 'Hoot',
    uri   => 'http://hexten.net/'
  );

=head3 C<< last >>

Get the most recent response (a hash ref). Useful in the case of an HTTP
error (which throws an exception).

=cut

sub _api {
  my ( $self, $service, $action, $need, $optional, @args ) = @_;
  my %args = (
    _need(
      $need, $optional,
      userid    => $self->userid,
      publickey => $self->publickey,
      @args
    ),
    action => $action
  );
  my $resp
   = $self->_ua->post( join( '/', API, $service ), Content => \%args );
  my $rd = $self->{last} = eval { JSON->new->decode( $resp->content ) };
  my $err = $@;
  if ( $resp->is_error ) {
    croak join ' ', @{$rd}{ 'response_code', 'response_message' }
     if !$err && $rd->{status} eq 'error';
    croak $resp->status_line;
  }
  croak $err if $err;    # Only report errors parsing JSON we have a 200
  return $rd;
}

sub api {
  my ( $self, $service, $action, @args ) = @_;
  return $self->_api( $service, $action, [], undef, @args );
}

sub _make_ua {
  my $self = shift;
  my $ua   = LWP::UserAgent->new;
  $ua->agent( join ' ', __PACKAGE__, $VERSION );
  #  $ua->add_handler(
  #    request_send => sub {
  #      shift->header( Authorization => $self->_auth_header );
  #    }
  #  );
  return $ua;
}

#sub _auth_header {
#  my $self = shift;
#  return 'Basic '
#   . encode_base64( join( ':', $self->userid, $self->publickey ), '' );
#}

sub _ua {
  my $self = shift;
  return $self->{_ua} ||= $self->_make_ua;
}

=head2 Procedural Interface

The following convenience subroutine may be exported:

=head3 C<< withings >>

Send a notification. 

  withings(
    userid  => 'alice',
    secret    => 'x3122b4c4d3bad5e8d7397f0501b617ce60afe5d',
    to        => 'hexten',
    msg       => 'Testing...',
    label     => 'Test',
    title     => 'Hoot',
    uri       => 'http://hexten.net/'
  );

=cut

sub withings {
  my %opt = _need( [], undef, @_ );
  return WWW::Withings->new( map { $_ => delete $opt{$_} }
     qw( userid secret ) )->send_notification( %opt );
}

1;
__END__

=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Andy Armstrong  C<< <andy@hexten.net> >>.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
