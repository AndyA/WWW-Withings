#!perl

use strict;
use warnings;

use Test::More tests => 12;
use JSON;
use WWW::Withings;

sub want_error(&$;$) {
  my ( $cb, $re, $msg ) = @_;
  $msg = 'error' unless $msg;
  eval { $cb->() };
  ok $@, "$msg: threw error";
  like $@, $re, "$msg: error matches";
}

{
  my $HR;

  sub patch_ua {
    my $wi = shift;
    $wi->_ua->add_handler( request_send => sub { $HR->( @_ ) } );
  }

  sub handle_request(&) { $HR = shift }
}

sub check_request {
  my ( $req, $wi ) = @_;
  is $req->method, 'POST', 'method is POST';
}

sub response($) {
  my $cont = shift;
  my $resp = HTTP::Response->new;
  $resp->content_type( 'application/json' );
  $resp->content( JSON->new->encode( $cont ) );
  $resp->code( 200 );
  return $resp;
}

sub decode_uri {
  my $str = shift;
  $str =~ s/\+/%20/g;
  $str =~ s/%([0-9a-f]{2})/chr hex $1/eig;
  return $str;
}

sub decode_form {
  my $cont = shift;
  my $vars = {};
  for my $arg ( split /&/, $cont ) {
    die "Bad arg: $arg" unless $arg =~ /(.+?)=(.+)/;
    $vars->{ decode_uri( $1 ) } = decode_uri( $2 );
  }
  return $vars;
}

want_error { WWW::Withings->new } qr{Missing}i, 'missing args';
want_error { WWW::Withings->new( 'foo' ) } qr{a number}i,
 'odd number of args';
want_error {
  WWW::Withings->new(
    userid    => 'alice',
    publickey => '123123',
    foo       => 1
  );
}
qr{Illegal}i, 'illegal args';

ok my $wi = WWW::Withings->new(
  userid    => '194681',
  publickey => '544c37c05e445b3b'
 ),
 'new';

isa_ok $wi, 'WWW::Withings';
patch_ua( $wi );

handle_request {
  my $req = shift;
  check_request( $req, $wi );
  is $req->uri, 'http://wbsapi.withings.net/once', 'uri';
  is_deeply decode_form( $req->content ),
   {
    userid    => '194681',
    publickey => '544c37c05e445b3b',
    action    => 'probe'
   },
   'content';
  return response { status => 0 };
};

is_deeply $wi->probe, { status => 0 }, 'probe';

__END__

handle_request {
  my $req = shift;
  check_request( $req, $wi );
  is $req->uri, 'https://api.withings.com/v1/send_notification', 'uri';
  is_deeply decode_form( $req->content ),
   {
    to    => 'hexten',
    msg   => 'Testing...',
    label => 'Test',
    title => 'Hoot',
    uri   => 'http://hexten.net/'
   },
   'content';
  return response {
    status           => 'success',
    response_code    => 2201,
    response_message => 'OK'
  };
};

is_deeply $wi->send_notification(
  to    => 'hexten',
  msg   => 'Testing...',
  label => 'Test',
  title => 'Hoot',
  uri   => 'http://hexten.net/'
 ),
 {
  status           => 'success',
  response_code    => 2201,
  response_message => 'OK'
 },
 'send_notification';

is_deeply $wi->api(
  'send_notification',
  to    => 'hexten',
  msg   => 'Testing...',
  label => 'Test',
  title => 'Hoot',
  uri   => 'http://hexten.net/'
 ),
 {
  status           => 'success',
  response_code    => 2201,
  response_message => 'OK'
 },
 'send_notification via api';

is_deeply $wi->last,
 {
  status           => 'success',
  response_code    => 2201,
  response_message => 'OK'
 },
 'last response';

want_error {
  $wi->send_notification(
    to      => 'hexten',
    msg     => 'Testing...',
    label   => 'Test',
    caption => 'Hoot',
    url     => 'http://hexten.net/'
  );
}
qr{Illegal.+\bcaption\b.+\burl\b}i, 'illegal';

handle_request {
  my $req  = shift;
  my $resp = response {
    status           => 'error',
    response_code    => 1101,
    response_message => 'Invalid Credentials'
  };
  $resp->code( 401 );
  $resp->message( 'Not authenticated' );
  return $resp;
};

want_error {
  $wi->send_notification(
    to  => 'hexten',
    msg => 'Testing...',
  );
}
qr{1101 Invalid Credentials}i, 'error from withings';

handle_request {
  my $req = shift;
  my $resp = response {};
  $resp->code( 401 );
  $resp->message( 'Not authenticated' );
  $resp->content( '' );
  return $resp;
};

want_error {
  $wi->send_notification(
    to  => 'hexten',
    msg => 'Testing...',
  );
}
qr{401 Not authenticated}i, 'error from LWP::UserAgent';

handle_request {
  my $req = shift;
  my $resp = response {};
  $resp->content( '' );
  return $resp;
};

want_error {
  $wi->send_notification(
    to  => 'hexten',
    msg => 'Testing...',
  );
}
qr{JSON}i, 'error parsing response';

# vim:ts=2:sw=2:et:ft=perl

