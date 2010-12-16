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
  my $withings = WWW::Withings->new(
    userid    => '194681',
    publickey => '544c37c05e445b3b'
  );
  
=head1 DESCRIPTION

http://www.withings.com/en/api/bodyscale

=cut

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

=head2 C<< for_user >>

Given an email address and password return a new C<WWW::Withings>
containing that user's C<userid> and C<publickey>.

  my $withings = WWW::Withings->new(
    userid    => '194681',
    publickey => '544c37c05e445b3b'
  );

  my $user_withings = $withings->for_user(
    'foo@example.com', 's3kr1t'
  );

=cut

sub for_user {
  my ( $self, $email, $password ) = @_;
  my $user  = $self->_get_user( $email, $password );
  my $class = ref $self;
  my @u     = map {
    $class->new( publickey => $_->{publickey}, userid => $_->{id} )
  } @{ $user->{body}{users} || [] };
  return wantarray ? @u : $u[0];
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

=head2 API Calls

API calls provide access to the Withings API.

On success they return a reference to a hash containing the response
from withings.com. On errors an exception will be thrown. In the case of
an error the response hash can be retrieved by calling C<last>.

=head3 C<< api >>

Direct access to the API. TODO

=head3 C<< last >>

Get the most recent response (a hash ref). Useful in the case of an HTTP
error (which throws an exception).

=cut

sub _err {
  my ( $self, $rc ) = @_;
  my %err = (
    0   => 'Operation was successfull',
    100 => 'The hash is missing, invalid, or '
     . 'does not match the provided email',
    247 => 'The userid is either absent or incorrect',
    250 => 'The userid and publickey provided '
     . 'do not match, or the user does not share its data',
    264  => 'The email address provided is either unknown or invalid',
    286  => 'No such subscription was found',
    293  => 'The callback URL is either absent or incorrect',
    294  => 'No such subscription could be deleted',
    304  => 'The comment is either absent or incorrect',
    2555 => 'An unknown error occured',
  );
  return $err{$rc} || "Unknown error (code $rc)";
}

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

Given an email and password compute a hash that may be used retrieve a
userid, publickey pair for a user.

Generally it won't be necessary to call this directly. Instead call
C<for_user> to retrieve a new WWW::Withings given an email address
and password.

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
