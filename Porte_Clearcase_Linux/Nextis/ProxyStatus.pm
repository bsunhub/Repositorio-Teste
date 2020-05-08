#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::ProxyStatus - a Perl package to query engine server status.
#

package Nextis::ProxyStatus;

# This package is used to query the status from the engine servers.

use strict;
use IO::Socket::INET;
use Nextis::Network;
use Nextis::Serialize;

# Create a new [<cc>]ProxyStatus[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    bless($self, $class);
    $self->{'errors'} = [];

    return $self;
}

# Add an error message to the list of error messages.
sub add_error
{
    my $self = shift;
    my $error = shift;

    push @{$self->{'errors'}}, $error;
    return $error;
}

# Return a reference to the list of error messages.
sub get_errors
{
    my $self = shift;

    my $ret = $self->{'errors'};
    $self->{'errors'} = [];
    return $ret;
}

# Query the current sessions from a daemon.
sub query_daemon_status
{
    my $self = shift;
    my $id = shift;
    my $host = shift;
    my $port = shift;
    my $user = shift;
    my $pass = shift;

    my $sock = IO::Socket::INET->new(Proto    => 'tcp',
                                     PeerAddr => $host,
                                     PeerPort => $port);
    if (! defined($sock)) {
        $self->add_error("$host:$port: can't connect to daemon");
        return {};
    }

    net_write($sock,
              "ADM_USERNAME: $user\n"
              . "ADM_PASSWORD: $pass\n"
              . "LIST_SESSIONS\n");
    my $ts = time();
    my $resp = net_read($sock);
    close($sock);

    if ($resp =~ /^ERROR/) {
        my $err = $resp;
        $err =~ s/\r?\n?$//;
        $self->add_error("$host:$port: $err");
        return {};
    }

    my $ret = Nextis::Serialize::deserialize($resp);
    $ret->{'req_timestamp'} = $ts;
    $ret->{'host'} = $host;
    $ret->{'port'} = $port;
    return $ret;
}

# Query the list of daemons from a shepherd.
sub query_shepherd_status
{
    my $self = shift;
    my $host = shift;
    my $port = shift;
    my $user = shift;
    my $pass = shift;

    my $sock = IO::Socket::INET->new(Proto    => "tcp",
                                     PeerAddr => $host,
                                     PeerPort => $port);

    if (! defined($sock)) {
        $self->add_error("$host:$port: can't connect to shepherd");
        return {};
    }

    net_write($sock,
              "USERNAME: $user\n"
              . "PASSWORD: $pass\n"
              . "LIST_DAEMONS\n");
    my $resp = net_read($sock);
    if (! defined($resp)) {
        $self->add_error("$host:$port: can't read shepherd response");
        close($sock);
        return undef;
    }
    close($sock);

    my %ret = ();
    my $i = 0;
    while ($resp =~ s/(.*)\n//) {
        my $line = $1;
        if ($line =~ /DAEMON (.+?)\@([0-9\.]+):(\d+)/) {
            my $daemon_id = $1;
            my $daemon_host = $2;
            my $daemon_port = $3;
            $daemon_host = $host;  # shepherd may respond 127.0.0.1
            $ret{$daemon_id} = $self->query_daemon_status($daemon_id,
                                                          $daemon_host,
                                                          $daemon_port,
                                                          $user, $pass);
        } else {
            #$ret{"bad_line_$i"} = $line;
            $i++;
        }
    }

    return \%ret;
}

# Query status from all shepherds in the given configuration.
sub query_global_status
{
    my $self = shift;
    my $cfg = shift;

    return {} unless $cfg;

    # get server list from config
    my @server_list = ();
    my $server_list = $cfg->get_value('cgi', 'servers');
    for my $s (split(/\s*,\s*/, $server_list)) {
        my ($server, $pref) = split(/:/, $s);
        next unless $server;
        my $addr = $cfg->get_value($server, 'address');
        next unless $addr;
        my ($host, $port) = split(/:/, $addr);
        push @server_list, {
            'server' => $server,
            'host' => $host,
            'port' => $port,
            'user' => $cfg->get_value($server, 'username') || '',
            'pass' => $cfg->get_value($server, 'password') || '',
        };
    }

    # query servers
    my $status = {};
    for my $s (@server_list) {
        my $id_prefix = '';
        $id_prefix = "$s->{'server'}:" if (scalar(@server_list) > 1);
        #$id_prefix = "$s->{'server'}:";
        my $r = $self->query_shepherd_status($s->{'host'}, $s->{'port'},
                                             $s->{'user'}, $s->{'pass'});
        for my $k (keys %{$r}) {
            $status->{$k} = $r->{$k};
            $status->{$k}->{'id_prefix'} = $id_prefix;
        }
    }

    return $status;
}

1;
