#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CQProxy - a Perl package to connect to engine servers.
#

package Nextis::CQProxy;

# This package handles the connection to an engine server and the
# corresponding ClearQuest session, from the client side.
#
# Usage example:
#
# [<code>]
# use Nextis::CQConnect();
# use Nextis::CQProxy();
#
# my $conn = new Nextis::CQConnect("config.cfg");
# my $proxy = new Nextis::CQProxy()
# $conn->connect($proxy) or die "Can't connect to session server";
# my $session = $proxy->get_cq_session();
#
# # use the session as a normal CQSession from the ClearQuest API:
# $session->UserLogon("user", "password", "database");
#
# # when done, close the connection to the session server:
# $proxy->close();
# [</code>]

use strict;
use Carp;
use IO::Socket;
use Fcntl;
use Digest::MD5;
use MIME::Base64;
use Nextis::Serialize;
use Nextis::CQObject;
use Nextis::Network;

# query result sort orders
$CQPerlExt::CQ_SORT_ASC = 1;
$CQPerlExt::CQ_SORT_DESC = 2;

# boolean operators for filters
$CQPerlExt::CQ_BOOL_OP_AND = 1;
$CQPerlExt::CQ_BOOL_OP_OR = 2;

# comparison operators for filters
$CQPerlExt::CQ_COMP_OP_EQ = 1;
$CQPerlExt::CQ_COMP_OP_NEQ = 2;
$CQPerlExt::CQ_COMP_OP_LT = 3;
$CQPerlExt::CQ_COMP_OP_LTE = 4;
$CQPerlExt::CQ_COMP_OP_GT = 5;
$CQPerlExt::CQ_COMP_OP_GTE = 6;
$CQPerlExt::CQ_COMP_OP_LIKE = 7;
$CQPerlExt::CQ_COMP_OP_NOT_LIKE = 8;
$CQPerlExt::CQ_COMP_OP_BETWEEN = 9;
$CQPerlExt::CQ_COMP_OP_NOT_BETWEEN = 10;
$CQPerlExt::CQ_COMP_OP_IS_NULL = 11;
$CQPerlExt::CQ_COMP_OP_IS_NOT_NULL = 12;
$CQPerlExt::CQ_COMP_OP_IN = 13;
$CQPerlExt::CQ_COMP_OP_NOT_IN = 14;


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

my $gen_id = sub {
    return Digest::MD5::md5_base64(rand(1000000));
};

my $gen_secret = sub {
    my $id = shift || $gen_id->();
    my $ts = time();
    return Digest::MD5::md5_base64($id . "frumps"
                                   . $ts . "zombo.com");
};

# Encrypt and return the given string.  The encryption (symmetric) key
# must have been generated with [<cc>]make_secret()[</cc>] or
# retrieved from a session where the key has been previously
# generated.
sub encrypt
{
    my $self = shift;
    my $str = shift;

    #print "encrypting '$str'\n";
    my $secret = $self->get_secret() || $gen_id->();
    while (length($secret) < length($str)) {
        $secret .= $secret;
    }
    $secret = substr($secret, 0, length($str));
    my $result = encode_base64("$secret" ^ "$str", '');
    $result =~ s/\+/\$/g;
    $result =~ s/\=//g;
    return $result;
}

# Decrypt a string encrypted with [<cc>]decrypt()[</cc>].
sub decrypt
{
    my $self = shift;
    my $str = shift || '';

    $str .= '=';
    $str =~ s/\$/+/g;
    $str = decode_base64($str);
    my $secret = $self->get_secret() || $gen_id->();
    while (length($secret) < length($str)) {
        $secret .= $secret;
    }
    $secret = substr($secret, 0, length($str));
    return "$secret" ^ "$str";
}

# Create a new [<cc>]CQProxy[</cc>] object to connect to a session server.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'session_id'} = undef;
    $self->{'session_secret'} = undef;
    $self->{'server'} = undef;
    $self->{'last_error'} = undef;
    bless($self, $class);

    return $self;
}

# Create a new [<cc>]CQObject[</cc>] object.  This is used internally
# to deserialize return values from the session server and should not
# be called directly.
sub create_object
{
    my $self = shift;
    my $val = shift;

    return undef unless defined($val);
    my @v = split(/\./, $val, 2);
    return new Nextis::CQObject($v[0], $v[1], $self);
}

# Return a string that identifies the object across connections to the
# same session.  You must call [<cc>]keep_ref[</cc>] in order to keep
# an object from being destroyed if you want to use this string in
# another connection to the session server.
sub get_object_string
{
    my $self = shift;
    my $obj = shift;

    return $obj->nx_name() . '.' . $obj->nx_id();
}

# Instruct the session server to keep the given object across connections.
sub keep_object
{
    my $self = shift;
    my $obj = shift;

    return $obj->nx_keep_ref(1);
}

# Return the last error message.
sub last_error
{
    return shift->{'last_error'};
}

# Set the last error message to be returned by [<cc>]last_error[</cc>].
sub set_last_error
{
    my $self = shift;
    my $err = shift;

    return $self->{'last_error'} = $err;
}

# Connect to the session server and create a new session.
# [<code>]
# %conf = (
#   'server' => '192.168.1.1:5678',
#   'username' => 'xxxxxx',
#   'password' => 'xxxxxx'
# );
# [</code>]
sub new_session
{
    my $self = shift;
    my %conf = @_;

    if (! defined($conf{'server'})) {
        carp "You must specify a server to connect to.";
        return undef;
    }

    my ($host, $port) = split(/:/, $conf{'server'});
    my $username = $conf{'username'};
    my $password = $conf{'password'};

    my $server = eval {
        IO::Socket::INET->new(Proto    => "tcp",
                              PeerAddr => $host,
                              PeerPort => $port);
      };
    if (! $server) {
        $self->set_last_error("Can't connect to $host:$port: $!");
        #carp "Can't connect to $host:$port to create a new session";
        return undef;
    }
    $server->autoflush(1);
    $self->{'server'} = $server;

    # Init new session
    my $new_port = undef;
    my $new_session_id = undef;
    $self->send_data("USERNAME: $username\nPASSWORD: $password\nNEW_SESSION\n");
    my $resp = $self->get_data() || '';
    $self->close();

    #print "-----------\n$resp\n------------\n";

    while ($resp =~ s/^([A-Za-z0-9_]+): (.*)\n//) {
        my $var = $1;
        my $val = $2;

        $val =~ s/[\r\n]//g;
        for ($var) {
            /^SESSION_ID$/ && do { $new_session_id = $val; last; };
            /^PORT$/ && do { $new_port = $val; last; };
            /^ERROR$/ && do {
                $self->set_last_error("$var: $val");
                return undef;
            };
            carp "BAD COMMAND FROM SERVER: '$var'";
        }
    }
    if (! defined($new_port)) {
        $self->set_last_error("Server didn't send port");
        return undef;
    }

    return $self->set_session("$new_session_id\@$host:$new_port");
}

# Return the session ID from the session.  This can be later passed to
# [<cc>]set_session[</cc>] to retrieve the same session from the
# session server.
sub get_session_id
{
    return shift->{'session_id'};
}

# Connect to the session server and re-use an existing server with ID
# '[<cc>]$session[</cc>]'.  Return the session_id, or
# [<cc>]undef[</cc>] if the session couldn't be reused.
sub set_session
{
    my $self = shift;
    my $session = shift;;

    my ($sess_id, $host_port) = split(/\@/, $session);
    my ($host, $port) = split(/:/, $host_port);

    my $server = eval {
        IO::Socket::INET->new(Proto    => "tcp",
                              PeerAddr => $host,
                              PeerPort => $port);
      };
    if (! $server) {
        $self->set_last_error($!);
        #carp "Can't connect to $host:$port";
        return undef;
    }
    $server->autoflush(1);
    $self->{'server'} = $server;

    my $n;
    my $str = "SESSION_ID: $sess_id\nSET_SESSION\n";
    $n = $self->send_data($str);
    if (! defined($n)) {
        $self->close();
        carp "Can't write to server";
        return undef;
    }

    my $resp = $self->get_data();
    if (! defined($resp)) {
        $self->close();
        carp "Error reading reply from server";
        return undef;
    }
    $resp =~ s/[\r\n]//g;
    if ($resp !~ /^([A-Za-z0-9_]+): (.*)/) {
        $self->set_last_error("Bad response from server: '$resp'");
        return undef;
    }
    my $status = $1;
    $sess_id = $2;
    if ($status ne 'SESSION_ID') {
        $self->set_last_error($resp);
        return undef;
    }
    return $self->{'session_id'} = "$sess_id\@$host:$port";
}

# Instruct the session server to terminate the session and close the
# connection to it.
sub end_session
{
    my $self = shift;

    my $str = "END_SESSION\n";
    
    my $n = $self->send_data($str);
    if (! defined($n)) {
        $self->close();
        carp "Can't write to server";
        return undef;
    }

    my $resp = $self->get_data();
    if (! defined($resp)) {
        $self->close();
        carp "Error reading reply from server";
        return undef;
    }

    if ($resp !~ /^OK/) {
        $resp =~ s/\r?\n//g;
        $self->set_last_error($resp);
        return undef;
    }

    $self->close();
    $self->{'session_id'} = undef;
    $self->{'session_secret'} = undef;
    $self->{'server'} = undef;
    $self->{'last_error'} = undef;
    return 1;
}

# Return [<cc>]1[</cc>] if connected to the server, [<cc>]0[</cc>] if not.
sub connected
{
    my $self = shift;

    return (defined($self->{'server'})) ? 1 : 0;
}

# Generate a new secret, set it in the session (if connected) and return it.
sub make_secret
{
    my $self = shift;

    $self->{'session_secret'} = $gen_secret->($self->{'session_id'});
    if ($self->connected()) {
        $self->set_variable('session_secret', $self->{'session_secret'});
    }
    return $self->{'session_secret'};
}

# Retrieve the secret from the session and return it.
sub get_secret
{
    my $self = shift;

    if (! defined($self->{'session_secret'}) && $self->connected()) {
        $self->{'session_secret'} = $self->get_variable('session_secret');
    }
    return $self->{'session_secret'};
}

# Send data to the server session.  This method should not be called
# directly.
sub send_data
{
    my $self = shift;
    my $data = shift;

    return net_write($self->{'server'}, $data);
}

# Retrieve data from the server session.  This method should not be
# called directly.
sub get_data
{
    my $self = shift;

    return net_read($self->{'server'});
}

# Send a file to the session server.  The file will be opened and sent.
sub send_file
{
    my $self = shift;
    my $filename = shift;

    if (! sysopen(SENDFILE, $filename, O_RDONLY|O_BINARY)) {
        $self->set_last_error("can't open $filename: $!");
        return undef;
    }

    my $f = $filename;
    if ($f =~ /\\/) {
        $f =~ s/^.*\\([^\\]+)$/$1/;
    } else {
        $f =~ s/^.*\/([^\/]+)$/$1/;
    }
    my $ret = $self->send_file_handle(\*SENDFILE, $f);

    close(SENDFILE);
    return $ret;
}

# Send a file to the session server, given its file handle and the
# filename it should have in the server.
sub send_file_handle
{
    my $self = shift;
    my $file = shift;
    my $filename = shift;

    if (! defined($self->{'server'})) {
        carp $self->set_last_error("can't send file: not connected!");
        return undef;
    }

    if (! defined($self->get_session_id())) {
        carp $self->set_last_error("can't send file: no session!");
        return undef;
    }

    my @st = stat($file);
    if (! @st) {
        $self->set_last_error("can't stat file: $!");
        return undef;
    }
    my $filesize = $st[7];

    my $str = "FILE_NAME: $filename\n"
        . "FILE_SIZE: $filesize\n"
        . "FILE_SEND\n";
    if (! $self->send_data($str)) {
        carp $self->set_last_error("send_file can't write to server!");
        return undef;
    }
    $str = $self->get_data();
    if (! defined($str)) {
        carp $self->set_last_error("send_file can't read from server!");
        return undef;
    }
    if ($str !~ /^OK/) {
        $self->set_last_error($str);
        return undef;
    }
    my $len = 0;
    my $error = 0;
    while ($len < $filesize) {
        my $x = $filesize - $len;
        $x = 4096 if ($x > 4096);
        my $data;
        my $r = sysread($file, $data, $x);
        if (! defined($r) || $r <= 0) {
            $error = 1;
            $data = ' ' x $x;
        }
        if (! $self->send_data($data)) {
            carp $self->set_last_error("send_file can't write to server!");
            return undef;
        }
        $len += length($data);
    }

    $str = $self->get_data();
    my $file_id = undef;
    if ($str =~ /^OK: (.*)$/) {
        $file_id = $1;
    } else {
        carp $self->set_last_error($str);
        return undef;
    }
    if ($error) {
        carp $self->set_last_error('error reading file');
        return undef;
    }
    return $file_id;
}

# Receive a file from the session server.  You must have a file ID
# associated with the file that you want to receive.  The file will be
# written to [<cc>]$filename[</cc>].
sub receive_file
{
    my $self = shift;
    my $file_id = shift;
    my $filename = shift;

    if (! defined($self->{'server'})) {
        carp $self->set_last_error("can't receive file: not connected!");
        return undef;
    }

    if (! defined($self->get_session_id())) {
        carp $self->set_last_error("can't receive file: no session!");
        return undef;
    }

    if (! sysopen(LOCALFILE, $filename,
                  O_WRONLY|O_TRUNC|O_CREAT|O_BINARY)) {
        carp $self->set_last_error("can't open $filename: $!");
        return undef;
    }

    my $str = "FILE_ID: $file_id\nFILE_RECEIVE\n";
    if (! $self->send_data($str)) {
        close(LOCALFILE);
        carp $self->set_last_error("receive_file can't write to server!");
        return undef;
    }

    $str = $self->get_data();
    if (! defined($str)) {
        close(LOCALFILE);
        carp $self->set_last_error("receive_file can't read from server!");
        return undef;
    }
    if ($str !~ /^OK: (\d+) bytes/) {
        close(LOCALFILE);
        carp $self->set_last_error($str);
        return undef;
    }
    my $filesize = $1;
    my $len = 0;
    my $error = 0;
    while ($len < $filesize) {
        my $data = $self->get_data();
        if (! defined($data)) {
            close(LOCALFILE);
            carp $self->set_last_error("receive_file can't write to server!");
            return undef;
        }
        my $r = length($data);
        last if ($r == 0);
        syswrite(LOCALFILE, $data);
        $len += $r;
    }

    close(LOCALFILE);
    return 1;
}

# Set the current user action to be viewed in the session status.
sub set_user_action
{
    my $self = shift;
    my $action = shift;
    my @parms = @_;

    return $self->fast_call('set_user_action', $action, @parms);
}

# Run a fast call in the server.
sub fast_call
{
    my $self = shift;
    my @parms = @_;

    if (! defined($self->{'server'})) {
        carp $self->set_last_error("can't make fast call: not connected!");
        return undef;
    }

    if (! defined($self->get_session_id())) {
        carp $self->set_last_error("can't make fast call: no session!");
        return undef;
    }

    my $str = "OBJECT: *\nMETHOD: fast_call\n";
    my $i = 0;
    for my $parm (@parms) {
        $str .= "PARM$i: " . Nextis::Serialize::serialize($parm) . "\n";
        $i++;
    }
    $str .= "CALL\n";
    $self->send_data($str);

    $str = $self->get_data();
    if (! defined($str)) {
        carp $self->set_last_error("fast call can't read from server!");
        return undef;
    }

    if (! defined($str)) {
        carp $self->set_last_error("fast call got bad response from server");
        return undef;
    }
    if ($str =~ /^ERROR:[0-9]+\((.*)\)$/s) {
        my $err = $1;
        #$err =~ s/[\r\n]//g;
        #$err =~ s/\.$//;
        die $err;
    }
    #print STDERR "$parms[0]: " . length($str) . " bytes\n";
    return Nextis::Serialize::deserialize($str, \&create_object, $self);
}

# Retrieve the [<cc>]ClearQuest[</cc>] session object for the session.
sub get_cq_session
{
    my $self = shift;

    return $self->fast_call('get_cq_session');
}

# Retrieve the [<cc>]ClearQuest[</cc>] admin session object for the session.
sub get_cq_admin_session
{
    my $self = shift;

    return $self->fast_call('get_cq_admin_session');
}

# Set a session variable in the session server.
sub set_variable
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    return $self->fast_call('set_variable', $name, $value);
}

# Retrieve the value of a previously set session variable from the
# session server.
sub get_variable
{
    my $self = shift;
    my $name = shift;

    return $self->fast_call('get_variable', $name);
}

# Close the connection to the session server.
sub close
{
    my $self = shift;

    close($self->{'server'}) if (defined($self->{'server'}));
    $self->{'server'} = undef;
    return 1;
}

1;
