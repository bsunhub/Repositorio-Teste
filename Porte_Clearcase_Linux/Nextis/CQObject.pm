#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CQObject - a Perl package that encapsulates a ClearQuest
# object in the server.

package Nextis::CQObject;

# This package poses as every class in the ClearQuest API.  When a
# method is called in an object of this class, a remote call is made
# to perform the call in the server.

use strict;
use Carp;
use IO::Socket;
use Nextis::Serialize;
use Nextis::CQProxy;

our $AUTOLOAD;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}

# Create a new [<cc>]CQObject[</cc>].  This function usually doesn't
# have to be called, CQObjects are automatically created by
# [<cc>]CQProxy[</cc>] when unserializing responses from the session
# server.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $name = shift;
    my $id = shift;
    my $server = shift;

    $self->{'name'} = $name;
    $self->{'id'} = $id;
    $self->{'server'} = $server;
    $self->{'keep_ref'} = 0;
    bless($self, $class);

    return $self;
}

# Return the name of the CQObject.
sub nx_name { return shift->{'name'}; }

# Return the ID of the CQObject.
sub nx_id { return shift->{'id'}; }

# Define whether the object will be kept in the server even when it is
# not referenced anymore by the client.  [<cc>]$keep[</cc>] must be
# [<cc>]1[</cc>] to keep the object in the server, or [<cc>]0[</cc>]
# to destroy it immediatelly.
sub nx_keep_ref
{
    my $self = shift;
    my $keep = shift;

    my $old = $self->{'keep_ref'};
    if (defined($keep)) {
        $self->{'keep_ref'} = $keep;
        $self->nx_call_method('DESTROY') unless $keep;
    }

    return $old;
}

# Call a method of the object in the server.  This is used internally
# when you call an undefined method in the client and should not be
# called directly.
sub nx_call_method
{
    my $self = shift;
    my $method = shift;
    my @parms = @_;

    my $server = $self->{'server'};
    if (! defined($server) || ! $server->connected()) {
        if ($method ne 'DESTROY') {
            carp "can't call method $AUTOLOAD: not connected to server";
        }
        return undef;
    }

    return undef if ($method eq 'DESTROY' && $self->{'keep_ref'});

    my $str =
        "OBJECT: " . Nextis::Serialize::serialize($self) . "\n" .
        "METHOD: $method\n";

    my $i = 0;
    for my $parm (@parms) {
        $str .= "PARM$i: " . Nextis::Serialize::serialize($parm) . "\n";
        $i++;
    }
    $str .= "CALL\n";

    # Send call
    if (! defined($server->send_data($str))) {
        carp "Error calling remote method '$method': $!";
        return undef;
    }

    # Read reply
    my $ret = $server->get_data();
    if (! defined($ret)) {
        carp "Error reading response for method '$method': $!";
        return undef;
    }

    # Parse the reply and return it
    if ($ret eq '') { return undef; }
    if ($ret =~ /^ERROR:[0-9]+\((.*)\)$/s) {
        my $err = $1;
        #$err =~ s/[\r\n]//g;
        #$err =~ s/\.$//;
        croak $err;
    }
    return Nextis::Serialize::deserialize($ret,
                                          \&Nextis::CQProxy::create_object,
                                          $server);
}

# This is the method called by Perl to make remote calls to the
# session server.  Do not call this directly.
sub AUTOLOAD
{
    my $self = shift;
    my @parms = @_;

    my $method = $AUTOLOAD;
    $method =~ s/.*://;

    return $self->nx_call_method($method, @parms);
}

1;
