
package LWP::Protocol::Coro::http;

use strict;
use warnings;

use version; our $VERSION = qv('v1.0.3');

use AnyEvent::HTTP qw( http_request );
use Coro::Channel  qw( );
use HTTP::Response qw( );
use LWP::Protocol  qw( );

our @ISA = 'LWP::Protocol';

LWP::Protocol::implementor($_, __PACKAGE__) for qw( http https );


sub _set_response_headers {
   my ($response, $headers) = @_;

   my %headers = %$headers;

   $response->protocol( "HTTP/".delete($headers{ HTTPVersion }) )
      if $headers{ HTTPVersion };
   $response->code(             delete($headers{ Status      }) );
   $response->message(          delete($headers{ Reason      }) );

   # Uppercase headers are pseudo headers added by AnyEvent::HTTP.
   $headers{"X-AE-$_"} = delete($headers{$_}) for grep /^(?!X-)[A-Z]/, keys(%headers);

   if (exists($headers->{'set-cookie'})) {
      # Set-Cookie headers are very non-standard.
      # They cannot be safely joined.
      # Try to undo their joining for HTTP::Cookies.
      $headers{'set-cookie'} = [
         split(/,(?=\s*\w+\s*(?:[=,;]|\z))/, $headers{'set-cookie'})
      ];
   }

   $response->header(%headers);
}


sub request {
   my ($self, $request, $proxy, $arg, $size, $timeout) = @_;

   my $method  = $request->method();
   my $url     = $request->uri();
   my %headers;  $request->headers()->scan(sub { $headers{$_[0]} = $_[1]; });
   my $body    = $request->content_ref();

   # The status code will be replaced.
   my $response = HTTP::Response->new(599, 'Internal Server Error');
   $response->request($request);

   my $headers_avail = AnyEvent->condvar();
   my $data_channel = Coro::Channel->new(1);

   my %handle_opts;
   $handle_opts{read_size}     = $size if defined($size);
   $handle_opts{max_read_size} = $size if defined($size);

   my %opts = ( handle_params => \%handle_opts );
   $opts{body}    = $$body   if defined($body);
   $opts{timeout} = $timeout if defined($timeout);

   if ($proxy) {
      my $proxy_uri = URI->new($proxy);
      $opts{proxy} = [$proxy_uri->host, $proxy_uri->port, $proxy_uri->scheme];
   }

   # Let LWP handle redirects and cookies.
   my $guard = http_request(
      $method => $url,
      headers => \%headers,
      %opts,
      recurse => 0,
      on_header => sub {
         #my ($headers) = @_;
         _set_response_headers($response, $_[0]);
         $headers_avail->send();
         return 1;
      },
      on_body => sub {
         #my ($chunk, $headers) = @_;
         $data_channel->put(\$_[0]);
         return 1;
      },
      sub { # On completion
         # On successful completion: @_ = ('',     $headers)
         # On error:                 @_ = (undef,  $headers)

         # It is possible for the request to complete without
         # calling the header callback in the event of error.
         # It is also possible for the Status to change as the
         # result of an error. This handles these events.
         _set_response_headers($response, $_[1]);
         $headers_avail->send();
         $data_channel->put(\'');
      },
   );

   # We need to wait for the headers so the response code
   # is set up properly. LWP::Protocol decides on ->is_success
   # whether to call the :content_cb or not.
   $headers_avail->recv();

   return $self->collect($arg, $response, sub {
      return $data_channel->get();
   });
}


1;


__END__

=head1 NAME

LWP::Protocol::Coro::http - Coro-friendly HTTP and HTTPS backend for LWP


=head1 VERSION

Version 1.0.3


=head1 SYNOPSIS

    # Make HTTP and HTTPS requests Coro-friendly.
    use LWP::Protocol::Coro::http;

    # Or LWP::Simple, WWW::Mechanize, etc
    use LWP::UserAgent;

    # A reason to want LWP friendly to event loops.
    use Coro qw( async );

    my $ua = LWP::UserAgent->new();
    $ua->protocols_allowed([qw( http https )]);  # Playing it safe.

    for my $url (@urls) {
        async { process( $ua->get($url) ) };
    }


=head1 DESCRIPTION

L<Coro> is a cooperating multitasking system. This means
it requires some amount of cooperation on the part of
user code in order to provide parallelism.

This module makes L<LWP> more cooperative by plugging
in an HTTP and HTTPS protocol implementor powered by
L<AnyEvent::HTTP>.

All LWP features and configuration options should still be
available when using this module.


=head1 SEE ALSO

=over 4

=item * L<LWP::Protocol::AnyEvent::http>

An newer implementation of this module that doesn't require L<Coro>.
These two modules are developed in parallel.

=item * L<Coro>

An excellent cooperative multitasking library assisted by this module.

=item * L<AnyEvent::HTTP>

Powers this module.

=item * L<LWP::Simple>, L<LWP::UserAgent>, L<WWW::Mechanize>

Affected by this module.

=item * L<Coro::LWP>

An alternative to this module for users of L<Coro>. Intrusive, which results
in problems in some unrelated code. Doesn't support HTTPS. Supports FTP and NTTP.

=item * L<AnyEvent::HTTP::LWP::UserAgent>

An alternative to this module. Doesn't help code that uses L<LWP::Simple> or L<LWP::UserAgent> directly.

=back


=head1 BUGS

Please report any bugs or feature requests to C<bug-LWP-Protocol-Coro-http at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=LWP-Protocol-Coro-http>.
I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc LWP::Protocol::Coro::http

You can also look for information at:

=over 4

=item * Search CPAN

L<http://search.cpan.org/dist/LWP-Protocol-Coro-http>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=LWP-Protocol-Coro-http>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/LWP-Protocol-Coro-http>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/LWP-Protocol-Coro-http>

=back


=head1 AUTHORS

Eric Brine, C<< <ikegami@adaelis.com> >>

Max Maischein, C<< <corion@cpan.org> >>

Graham Barr, C<< <gbarr@pobox.com> >>


=head1 COPYRIGHT & LICENSE

No rights reserved.

The author has dedicated the work to the Commons by waiving all of his
or her rights to the work worldwide under copyright law and all related or
neighboring legal rights he or she had in the work, to the extent allowable by
law.

Works under CC0 do not require attribution. When citing the work, you should
not imply endorsement by the author.


=cut
