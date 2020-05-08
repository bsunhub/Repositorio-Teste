#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::DumbHTTPServer - a Perl package implementing a dumb HTTP server.
#

package Nextis::DumbHTTPServer;

# This package implements a very simple HTTP server.
#
# Usage example:
# [<code>]
# sub process_request {
#     my ($server, $sock, $data) = @_;
#     $sock->print("HTTP/1.0 200 OK\r\n");
#     $sock->print("Content-type: text/html\r\n\r\n");
#     $sock->print("<html><body>Hi!</body></html>\n");
# }
# my $server = new Nextis::DumbHTTPServer(8080);
# $server->read_mime_types($mime_types_filename);  # for serving static files
# while (42) {
#     $server->process_request(10, \&process_request);
# }
# [</code>]
#
# A more realistic usage would be to call select() on $server->sock()
# to detect when a client has connected.

use strict;
use Carp;
use IO::Socket;
use MIME::Base64;

our $AUTOLOAD;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# Create a new HTTP server.  If a port is given, start listeing for
# connections in the given port (or returns [<cc>]undef[</cc>] on
# error).
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'mime_types'} = {};
    $self->{'sock'} = undef;
    $self->{'user_auth'} = {};
    bless($self, $class);

    my $port = shift;
    if (defined($port) && $port) {
        return undef unless ($self->open($port));
    }

    return $self;
}

sub add_user_auth
{
    my $self = shift;
    my $username = shift;
    my $password = shift;

    $self->{'user_auth'}->{$username} = $password;
    return 1;
}

sub check_user_auth
{
    my $self = shift;
    my $req = shift;

    my $user_auth = $self->{'user_auth'};
    my $path = $req->{'path'};
    my $headers = $req->{'headers'};

    my @auths = map { ($_ =~ /^authorization\s*:\s+(.*)$/i) ? ($1) : () } @{$headers};
    for my $auth (@auths) {
        my ($type, $data) = split(/\s+/, $auth, 2);
        if ($type =~ /basic/i) {
            my ($user, $pass) = split(/:/, decode_base64($data), 2);
            if (defined($user)
                && defined($pass)
                && exists($user_auth->{$user})
                && $user_auth->{$user} eq $pass) {
                return 1;
            }                
        }
    }

    return 0;
}

# Send a "Not Found" response to the client given its connection socket.
sub http_not_found
{
    my $self = shift;
    my $sock = shift;

    $sock->print("HTTP/1.1 404 Not Found\r\n");
    $sock->print("Connection: close\r\n");
    $sock->print("Content-type: text/html\r\n\r\n");
    $sock->print("<h1>404 Not Found</h1>\n");
    $sock->print("<p>The requested document was not found on this server.</p>\n");
}

# Send a "Authorization Required" response to the client given its connection socket.
sub http_authorization_required
{
    my $self = shift;
    my $sock = shift;
    my $realm = shift;

    $realm = 'Basic Realm' unless (defined($realm));

    $sock->print("HTTP/1.1 401 Authorization Required\r\n");
    $sock->print("WWW-Authenticate: Basic realm=\"$realm\"");
    $sock->print("Connection: close\r\n");
    $sock->print("Content-type: text/html\r\n\r\n");
    $sock->print("<h1>401 Authorization Required</h1>\n");
    $sock->print("<p>An authorization is required to access this page.</p>\n");
}

# Send a "Not Authorized" response to the client given its connection socket.
sub http_not_authorized
{
    my $self = shift;
    my $sock = shift;

    $sock->print("HTTP/1.1 503 Not Authorized\r\n");
    $sock->print("Connection: close\r\n");
    $sock->print("Content-type: text/html\r\n\r\n");
    $sock->print("<h1>503 Not Authorized</h1>\n");
    $sock->print("<p>An authorization is required to access this page.</p>\n");
}

sub _get_http_date
{
    my $ts = shift;

    my @dow = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    my @t = gmtime($ts);
    return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
                   $dow[$t[6] % 7],
                   $t[3], $mon[$t[4]], $t[5] + 1900,
                   $t[2], $t[1], $t[0]);
}

# Send a file to the client given the connection socket to it.
#
# This function sends all the required HTTP headers.  If no mime type
# is given, the function tries to detect it from the file extension.
sub send_file
{
    my $self = shift;
    my $sock = shift;
    my $filename = shift;
    my $mime_type = shift;

    # open the file and get its size
    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        $self->http_not_found($sock);
        return undef;
    }
    binmode($fh);
    my @st = stat($filename);
    if (! @st) {
        close($fh);
        $self->http_not_found($sock);
        return undef;
    }
    my $file_mtime = $st[9];
    my $file_size = $st[7];

    if (! defined($mime_type)) {
        $mime_type = $self->get_mime_type($filename);
    }

    my $cur_date = _get_http_date(time());
    my $last_modified = _get_http_date($file_mtime);
    my $expires = _get_http_date(time() + 86400);

    $sock->print("HTTP/1.1 200 OK\r\n");
    $sock->print("Connection: close\r\n");
    $sock->print("Date: $cur_date\r\n");
    $sock->print("Last-Modified: $last_modified\r\n");
    $sock->print("Expires: $expires\r\n");
    $sock->print("Content-Length: $file_size\r\n");
    $sock->print("Content-Type: $mime_type\r\n");
    $sock->print("\r\n");
    my $len = 0;
    my $error = 0;
    while ($len < $file_size) {
        my $x = $file_size - $len;
        $x = 4096 if ($x > 4096);
        my $data;
        my $n = sysread($fh, $data, $x);
        if (! defined($n) || $n <= 0) {
            $error = 1;
            $data = ' ' x $x;
        }
        $sock->print($data);
        $len += length($data);
    }
    close($fh);
    return 1;
}

# Read the mime types from the given file (in the format of the
# "mime.types" file from Apache).
sub read_mime_types
{
    my $self = shift;
    my $filename = shift;

    $self->{'mime_types'} = {};
    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        return undef;
    }
    while (<$fh>) {
        chomp;
        s/\#.*$//;
        s/\r//g;
        next if /^\s+$/;
        my ($name, $exts) = split(/\s+/, $_, 2);
        next if (! defined($name) || ! defined($exts)
                 || $name eq '' || $exts eq '');
        for my $ext (split(/\s+/, $exts)) {
            $self->{'mime_types'}->{$ext} = $name;
        }
    }
    close($fh);
    return 1;
}

# Return the mime type of the given extension, or [<cc>]undef[</cc>] if
# there's no registered mime type for the extension.
sub get_extension_mime_type
{
    my $self = shift;
    my $ext = shift;

    if (exists($self->{'mime_types'}->{$ext})) {
        return $self->{'mime_types'}->{$ext};
    }
    return undef;
}

# Return the mime type for the given filename (or 'text/plain' if the
# mime type is unknown).
sub get_mime_type
{
    my $self = shift;
    my $filename = shift;

    my $type = undef;
    if ($filename =~ m|([^/\.]+)$|) {
        my $ext = $1;
        $type = $self->get_extension_mime_type($ext);
    }
    return 'text/plain' unless defined($type);
    return $type;
}

# Start listening on the specified port.  Return [<cc>]undef[</cc>]
# on error.
sub open
{
    my $self = shift;
    my $port = shift;

    my $sock = IO::Socket::INET->new('Proto'     => 'tcp',
                                     'LocalPort' => $port,
                                     'Listen'    => SOMAXCONN,
                                     'Reuse'     => 1);
    return undef unless $sock;
    $self->{'sock'} = $sock;
    $self->{'sock'}->listen(5);
    return 1;
}

# Return the socket used for listening, or [<cc>]undef[</cc>] if the
# listening socket is not open.
sub sock
{
    my $self = shift;

    return $self->{'sock'};
}

# Accept a connection, read a request and call the given function to
# generate the response.  Return [<cc>]undef[</cc>] on error, or
# [<cc>]1[</cc>] if the request was read and processed.
#
# After a connection is accepted, the function tries to read the client
# HTTP request for up to $timeout seconds before giving up.
#
# The given function is called as:
#
# [<code>]
#   $func->($server, $sock, $req_data);
# [</code>]
#
# Where [<cc>]$server[</cc>] is the [<cc>]DumbHTTPServer[</cc>]
# object, [<cc>]$sock[</cc>] is the socket for the connection with the
# client and [<cc>]$req_data[</cc>] is a reference to a hash
# containing data for the connection:
#
# [<code>]
#  $req_data = {  
#      'path' => "(the requested URI)",
#      'version' => "(the protocol version used in the client request)",
#      'headers' => [ "(headers sent by the client)", ... ],
#  };
# [</code>]
#
# The function is responsible for sending ALL data to the client,
# including the response headers (starting with something like
# [<cc>]"HTTP/1.0 200 OK\r\n"[</cc>]).
sub process_request
{
    my $self = shift;
    my $timeout = shift;
    my $func = shift;
    my $log = shift;

    my $sock = $self->{'sock'}->accept();
    my $req_data = '';
    my $ts = time();

    # read headers
    while ($req_data !~ /\r\n\r\n/) {
        if ($ts + $timeout < time()) {
            $sock->shutdown(2);
            return undef;
        }
        my $str = '';
        my $n = sysread($sock, $str, 1024);
        if (! defined($n) || $n <= 0) {
            $sock->shutdown(2);
            return undef;
        }
        $req_data .= $str;
    }
    my ($req, $post_data) = split(/\r\n\r\n/, $req_data);
    $post_data = '' unless defined($post_data);

    my @headers = split(/\r\n/, $req);
    for (@headers) { s/\r\n$//; }

    # check if there's a content-length
    for my $header (@headers) {
        if ($header =~ /^content-length\s*:\s*(\d+)$/i) {
            my $len = $1;
            if ($len > 0) {
                my $cur_len = length($post_data);
                while ($cur_len < $len && $ts + $timeout > time()) {
                    my $str = '';
                    my $read_len = $len - $cur_len;
                    $read_len = 1024 if ($read_len > 1024);
                    my $n = sysread($sock, $str, $read_len);
                    if (! defined($n) || $n <= 0) {
                        $sock->shutdown(2);
                        return undef;
                    }
                    $post_data .= $str;
                    $cur_len += length($str);
                }
                if ($cur_len < $len) {
                    # timeout
                    return undef;
                }
            }
        }
    }

    my $line = shift(@headers);
    if ($line =~ /^(GET|POST)\s+([^\s]+)\s+HTTP\/([\d.]+)\s*$/) {
        my $method = $1;
        my $path = $2;
        my $version = $3;
        my $req_data = {
            'method' => $method,
            'path' => $path,
            'post_data' => $post_data,
            'version' => $version,
            'headers' => \@headers,
        };
        if (ref($func) eq 'CODE') {
            my $ok = eval {
                $func->($self, $sock, $req_data);
                1;
            };
            if (! $ok) {
                if ($log) {
                    $log->log("HTTP processor died: $@");
                } else {
                    print "HTTP processor died: $@\n";
                }
            }
        } else {
            $sock->print("HTTP/1.1 500 Internal Server Error\r\n");
            $sock->print("Connection: close\r\n");
            $sock->print("Content-type: text/html\r\n");
            $sock->print("\r\n");
            $sock->print("<html><body><h1>Internal Server Error</h1>\n<p>No response function defined!</p></body></html>\n");
        }
    } else {
        $sock->print("HTTP/1.1 400 Unsupported Request\r\n");
        $sock->print("Connection: close\r\n");
        $sock->print("Content-type: text/html\r\n");
        $sock->print("\r\n");
        $sock->print("<html><body>This webserver understands only GET and POST requests!<br><pre>$req</pre></body></html>\n");
    }
    $sock->shutdown(2);
    return 1;
}

# Close the listening socket.
sub close
{
    my $self = shift;

    my $ret = $self->{'sock'}->shutdown(2);
    $self->{'sock'} = undef;
    return $ret;
}

1;
