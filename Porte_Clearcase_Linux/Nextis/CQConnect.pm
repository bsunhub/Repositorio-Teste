#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CQConnect - a Perl package to connect to engine servers.
#

package Nextis::CQConnect;

# This package is used to estabilish a connection to an engine server.
# The package reads a configuration file specifying the potentially
# available servers and the preferences to give to each server.
#
# If one or more servers don't respond, they are ignored and other
# servers are tried until a connection is estabilished or there are no
# more servers.

use strict;
use Nextis::CQProxy;
use Nextis::Config;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# Create a new [<cc>]CQConnect[</cc>] object to connect to a session server.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'srv_list'} = [];
    bless($self, $class);

    my $config_file = shift || '';
    my $section = shift || '';

    if ($config_file) {
        $self->get_server_list($config_file, $section);
    }

    return $self;
}

# Set the last error, which can be read with [<cc>]last_error()[</cc>].
sub set_last_error
{
    my $self = shift;
    my $err = shift;

    $self->{'last_error'} = $err;
}

# Return the last error set with [<cc>]set_last_error()[</cc>].
sub last_error
{
    return shift->{'last_error'};
}

# Normalize the weights of the servers in the server list.  Return the
# number of active servers.
sub norm_server_weights
{
    my $self = shift;

    my $num_servers = 0;
    my $total_weight = 0;
    for my $s (@{$self->{'srv_list'}}) {
        if ($s->[2]) {
            $num_servers++;
            $total_weight += $s->[1];
        }
    }
    if ($total_weight <= 0) {
        return undef;
    }
    for my $s (@{$self->{'srv_list'}}) {
        if ($s->[2]) {
            $s->[1] /= $total_weight;
        }
    }
    return $num_servers;
}

# Get the server from a configuration.  [<cc>]$cfg[</cc>] may be the
# name of the configuration file or a [<cc>]Nextis::Config[</cc>]
# object.  [<cc>]$section[</cc>] is the name of the configuration
# section to retrieve the server list (from the [<cc>]server[</cc>]
# configuration variable).  If it is not specified, [<cc>]'cgi'[</cc>]
# is used.
sub get_server_list
{
    my $self = shift;
    my $cfg = shift;
    my $section = shift || 'cgi';

    if (ref($cfg) eq '') {
        my $conf = new Nextis::Config($cfg);
        if (! $conf) {
            $self->set_last_error("Can't read CGI configuration from '$cfg'");
            return undef;
        }
        $cfg = $conf;
    }
    if (! $cfg) {
        $self->set_last_error("Bad configuration");
        return undef;
    }

    my $servers = $cfg->get_value($section, 'servers');
    if (! defined($servers) || $servers eq '') {
        $self->set_last_error("No session servers defined in configuration");
        return undef;
    }

    # scan the CGI server list and normalize the relative weights
    my @servers = split(/\s*,\s*/, $servers);
    my @srv_list = ();
    for my $s (@servers) {
        my ($server, $weight) = split(/:/, $s);
        if (! defined($weight)) {
            $weight = 1;
        }
        my $server_cfg = $cfg->get_section($server);
        next unless $server_cfg;
        push @srv_list, [ $server_cfg, $weight, 1 ];
    }

    @srv_list = sort { $a->[1] <=> $b->[1] } @srv_list;
    $self->{'srv_list'} = \@srv_list;
    $self->norm_server_weights();
    return 1;
}

# Try the next server in configuration.  Return true if the connection
# was successful, [<cc>]0[</cc>] if it failed, or [<cc>]undef[</cc>] if
# there are no more servers to try.
sub try_next_server
{
    my $self = shift;
    my $conn = shift;

    return undef unless $self->norm_server_weights();

    my $num = rand();
    for my $s (@{$self->{'srv_list'}}) {
        next unless $s->[2];
        $num -= $s->[1];
        if ($num <= 0) {
            my $srv = $s->[0];
            my $r = $conn->new_session('server' => $srv->{'address'},
                                       'username' => $srv->{'username'},
                                       'password' => $srv->{'password'});
            print STDERR "-> tried '$srv->{'address'}': " . (($r)?1:0) . "\n";
            return $r if $r;
            $s->[2] = 0;  # don't try it again
            return 0;
        }
    }
    return 0;
}

# Try to make a connection, trying all servers.  Return true in
# success, [<cc>]undef[</cc>] on failure.
sub connect
{
    my $self = shift;
    my $conn = shift;

    my $ret;
    do {
        $ret = $self->try_next_server($conn);
        return $ret if ($ret);
    } while (defined($ret));

    $self->set_last_error("ERROR: there are no available servers.");
    return undef;
}

1;
