#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::ChatSession - a Perl package manage a Chat session.
#

package Nextis::ChatSession;

# This package manages a chat session for the ClearQuest web client.

use strict;
use Carp;
use Digest::MD5;

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

# Create a new [<cc>]Nextis::ChatSession[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'id'} = $gen_id->();
    $self->{'last_tx'} = time();
    $self->{'tx_info'} = {};
    $self->{'lines'} = [];
    $self->{'clients'} = {};
    $self->{'req_help'} = 0;

    bless($self, $class);
    return $self;
}

# Return the session id.
sub get_id
{
    my $self = shift;
    return $self->{'id'};
}

# Set the last transmission timestamp in the session.
sub set_last_tx
{
    my $self = shift;
    my $ts = shift || time();

    return $self->{'last_tx'} = $ts;
}

# Return the last transmission timestamp in the session, as set by
# [<cc>]set_last_tx()[</cc>].
sub last_tx
{
    my $self = shift;
    
    return $self->{'last_tx'};
}

# Set the "help requested" flag.
sub set_req_help
{
    my $self = shift;
    my $req_help = shift;

    $self->{'req_help'} = $req_help;
    return 1;
}

# Get the "help requested" flag.
sub get_req_help
{
    my $self = shift;
    
    return $self->{'req_help'};
}

# Add a line to the chat lines history.
sub add_line
{
    my $self = shift;
    my $line = shift;

    push @{$self->{'lines'}}, $line;
}

# Return a reference to an array containing the chat lines.
sub get_lines
{
    my $self = shift;

    return $self->{'lines'};
}

# Add a client to the client list.  A client must be a reference to a
# hash which contains at least one key 'id' which uniquely identifies
# the client.
sub add_client
{
    my $self = shift;
    my $client = shift;

    $self->{'clients'}->{$client->{'id'}} = $client;
    return 1;
}

# Removes the given client from the client list.
sub remove_client
{
    my $self = shift;
    my $client = shift;

    if (exists($self->{'clients'}->{$client->{'id'}})) {
        delete $self->{'clients'}->{$client->{'id'}};
        return 1;
    }
    return undef;
}

# Returns the number of clients in the client list.
sub num_clients
{
    my $self = shift;

    return scalar(keys %{$self->{'clients'}});
}

# Returns a reference to an array containing the client list.
sub list_clients
{
    my $self = shift;

    return [ values %{$self->{'clients'}} ];
}

1;
