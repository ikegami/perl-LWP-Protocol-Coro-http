#!perl -w
use strict;
use Test::More;

use LWP::Protocol::Coro::http;
use LWP::UserAgent;

plan tests => 4;

my $client = LWP::UserAgent->new();

my $url = 'http://doesnotexist.example';
diag "Retrieving URL: " . $url;

my $chunk_count = 0;
my $res = $client->get("${url}", ":content_cb" => sub { ++$chunk_count });
ok !$res->is_success, "The request was not successfull, as planned";
like $res->code, qr/^5\d\d/, "We caught the remote error (5xx)";
is $res->content, '', "We got an empty response";
is $chunk_count, 0, "We received no chunks either";
