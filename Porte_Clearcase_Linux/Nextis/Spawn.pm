#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::Spawn - a Perl package to read configuration files.
#

package Nextis::Spawn;

# This package reads and parses a configuration file.

use strict;

use POSIX ":sys_wait_h";
use IO::Socket;
use IPC::Open3;

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

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'sock'} = undef;
    $self->{'cmdline'} = [];
    $self->{'pid'} = undef;
    $self->{'last_error'} = '';
    bless($self, $class);

    my @cmdline = @_;
    if (scalar(@cmdline) > 0 && defined($cmdline[0])) {
        if (! $self->run(@cmdline)) {
            return undef;
        }
    }

    return $self;
}

sub last_error
{
    my $self = shift;

    return $self->{'last_error'};
}

sub set_last_error
{
    my $self = shift;
    my $message = shift;

    $self->{'last_error'} = $message;
}

sub run
{
    my $self = shift;
    my @cmdline = @_;

    # spawn the process
    my ($wfh, $rfh, $efh);
    my $pid = eval { open3($wfh, $rfh, $efh, @cmdline); };
    if (! defined($pid)) {
        my $err = $@;
        close($rfh) if defined($rfh);
        close($wfh) if defined($wfh);
        close($efh) if defined($efh);
        $rfh = $wfh = $efh = undef;
        exit(1);
    }

    my $oldfh = select($wfh); $| = 1; select($oldfh);
    print $wfh "START\r\n";
    my $resp = <$rfh>;
    close($rfh) if defined($rfh);
    close($wfh) if defined($wfh);
    close($efh) if defined($efh);

    # connect to it 
    $resp = '' unless defined($resp);
    $resp =~ s/^\s+//;
    $resp =~ s/\s+$//;
    $resp =~ s/\n//g;
    $resp =~ s/\r//g;
    if ($resp =~ /[^\d]/) {
        $self->set_last_error("can't connect to newly-spawned daemon (got reply: '$resp')");
        return undef;
    }
    my $host = '127.0.0.1';
    my $port = $resp;
    my $sock = IO::Socket::INET->new(Proto    => "tcp",
                                     PeerAddr => $host,
                                     PeerPort => $port);
    if (! $sock) {
        $self->set_last_error("can't connect to newly-spawned daemon (port: $port)");
        return undef;
    }

    $self->{'sock'} = $sock;
    $self->{'cmdline'} = [ @cmdline ];
    $self->{'pid'} = $pid;
    return 1;
}

sub sock
{
    my $self = shift;

    return $self->{'sock'};
}

sub close
{
    my $self = shift;

    if (! waitpid($self->{'pid'}, 0)) {
        print "ERROR WAITING FOR PID $self->{'pid'}\n";
    }
    my $ret = close($self->{'sock'});
    $self->{'sock'} = undef;
    return $ret;
}

1;
