#
# Copyright (C) 2004, 2005 Next Internet Solutions.
#
# Nextis::Network - a Perl package with network functions.
#

package Nextis::Network;

# This package handles communication in the network.  All
# communication should be made with these functions, they handle the
# data transmission protocol used in the engine.

use strict;
use Carp;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&net_read &net_write);
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# Write [<cc>]$data[</cc>] to the socket [<cc>]$sock[</cc>], prefixed
# by the data length (a 32-bit value in big-endian byte order).
# Return [<cc>]undef[</cc>] on error, or [<cc>]1[</cc>] on success.
sub net_write
{
    my $sock = shift;
    my $data = shift;

    if (! defined($sock)) {
        carp "net_write() called with undef socket";
        return undef;
    }
    if (! defined($data)) {
        carp "net_write() called with undef data";
        return undef;
    }

    my $h = pack('N', length($data) + 4);
    $data = $h . $data;
    my $len = length($data);
    my $done = 0;
    while ($done < $len) {
        my $n = $len - $done;
        my $r = syswrite($sock, $data, $n, $done);
        return undef unless defined($r);
        $done += $r;
    }
    return 1;
}

# Read data from from the socket, prefixed by the data length (a
# 32-bit value in big-endian byte order).  Return [<cc>]undef[</cc>]
# on error, or the read data.
sub net_read
{
    my $sock = shift;
    my $data;

    if (! defined($sock)) {
        carp "net_read() called with undef socket";
        return undef;
    }

    my $n = 0;
    while ($n < 4) {
        my $r = sysread($sock, $data, 4-$n, $n);
        return undef unless defined($r);
        return undef if ($r == 0);
        $n += $r;
    }
    my $len = unpack('N', $data);
    if ($len > 262144) {
        carp "net_read(): packet too big ($len)";
        return undef;
    }

    $data = undef;
    while ($n < $len) {
        my $x = $len - $n;
        my $r = sysread($sock, $data, $x, $n-4);
        return undef unless defined($r);
        return $data if ($r == 0);
        $n += $r;
    }
    return $data;
}

1;
