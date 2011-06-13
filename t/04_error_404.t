#!perl -w
use strict;
use Test::More;

use AnyEvent;
use LWP::Protocol::Coro::http;
use LWP::UserAgent;

# Check whether we can launch the local webserver
if (! eval {
    use lib '../inc', 'inc';
    require Test::HTTP::LocalServer;
    1;
}) {
    plan skip_all => "Couldn't launch test server: $@";
} else {
    plan tests => 4;
};

# Launch a timer
my $timer_events = 0;
my $t = AnyEvent->timer(
    after => 1, interval => 1, cb => sub { diag "Waiting for reply\n"; $timer_events++ }
);

my $client = LWP::UserAgent->new();

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);
my $url = $server->url;
diag "Retrieving URL: " . $url;

my $chunk_count = 0;
my $res = $client->get("${url}error/notfound/foo", ":content_cb" => sub {
    $chunk_count++
});
ok !$res->is_success, "The request was not successfull, as planned";
is $res->code, 404, "We caught the remote error (404)";
is $res->content, '', "We got an empty response";
is $chunk_count, 0, "We received no chunks either";

undef $t; # stop the timer

diag "Shutting down server";
$server->stop;
undef $server;
diag "Done";
