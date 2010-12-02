package WWW::Withings;

use warnings;
use strict;

use Carp;
use Data::Dumper;
use Digest::MD5 qw( md5_hex );
use JSON;
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
      fields  => [qw( userid publickey )],
      service => 'once',
      action  => 'probe',
    },
    get_measure => {
      fields   => [qw( userid publickey )],
      optional => [
        qw( startdate enddate meastype lastupdate category limit offset )
      ],
      service => 'measure',
      action  => 'getmeas',
      post    => sub { $_[0]->{body} }
    },
    get_user => {
      fields  => [qw( userid publickey )],
      service => 'user',
      action  => 'getbyuserid',
      post    => sub { @{ $_[0]->{body}{users} } }
    },
    get_otp => {
      fields  => [qw( userid publickey )],
      service => 'once',
      action  => 'get',
      post    => sub { $_[0]->{body}{once} }
    },
  );
  for my $m ( keys %meth ) {
    no strict 'refs';
    *{$m} = sub { shift->_api( $meth{$m}, @_ ) };
  }
}

sub _need {
  my ( $need, $optional, @args ) = @_;
  croak "Expected a number of key => value pairs"
   if @args % 2;
  my %args = @args;
  if ( defined $need ) {
    my @missing = grep { !defined $args{$_} } @$need;
    croak "Missing options: ", join( ', ', sort @missing )
     if @missing;
  }
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
    userid    => '194681',
    publickey => '544c37c05e445b3b'
  );

=cut

sub new {
  my $class = shift;
  return bless { _need( [ 'publickey', 'userid' ], [], @_ ) }, $class;
}

sub _get_user {
  my ( $self, $email, $password ) = @_;
  my $rs = $self->api(
    'account', 'getuserslist',
    email => $email,
    hash  => $self->hash( $email, $password )
  );
  return $rs;
}

sub for_user {
  my ( $self, $email, $password ) = @_;
  my $user  = $self->_get_user( $email, $password );
  my $class = ref $self;
  my @u     = map {
    $class->new( publickey => $_->{publickey}, userid => $_->{id} )
  } @{ $user->{body}{users} || [] };
  return wantarray ? @u : $u[0];
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
  my ( $self, $spec, @args ) = @_;
  my %args = (
    _need( $spec->{required}, $spec->{optional}, @args ),
    ( map { $_ => $self->$_() } @{ $spec->{fields} || [] } ),
    action => $spec->{action}
  );
  $spec->{pre}( \%args ) if $spec->{pre};
  my $resp = $self->_ua->post( join( '/', API, $spec->{service} ),
    Content => \%args );
  my $rd = $self->{last} = eval { JSON->new->decode( $resp->content ) };
  my $err = $@;
  croak $resp->status_line if $resp->is_error;
  croak $err
   if $err;    # Only report errors parsing JSON if we have a 200
  return $spec->{post}( $rd ) if $spec->{post};
  return $rd;
}

sub api {
  my ( $self, $service, $action, @args ) = @_;
  return $self->_api(
    {
      service => $service,
      action  => $action
    },
    @args
  );
}

sub _make_ua {
  my $self = shift;
  my $ua   = LWP::UserAgent->new;
  $ua->agent( join ' ', __PACKAGE__, $VERSION );
  return $ua;
}

sub _ua {
  my $self = shift;
  return $self->{_ua} ||= $self->_make_ua;
}

=head2 Other Methods

=head3 C<< hash >>

Given an email and password compute a hash that may be passed to TODO to
retrieve a userid, publickey pair for a user.

=cut

sub hash {
  my ( $self, $email, $password ) = @_;
  my $otp = $self->get_otp;
  croak "Couldn't get authentication information from withings.com"
   unless defined $otp;
  return lc md5_hex join ':', $email, md5_hex( $password ), $otp;
}

1;
__END__

=head1 AUTHOR

Andy Armstrong  C<< <andy@hexten.net> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Andy Armstrong  C<< <andy@hexten.net> >>.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
