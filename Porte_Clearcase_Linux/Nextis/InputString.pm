#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::InputString - a Perl package to read from strings.
#

package Nextis::InputString;

# This package implements a string reader.  It maintains a state of
# the current position in the string, and returns characters from this
# position when read.
#
# This package is used by [<cc>]Nextis::ExprParser[</cc>].

use strict;

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
    my $self = { };

    $self->{'input'} = undef;
    $self->{'pos'} = 0;
    bless($self, $class);

    my $val = shift;
    if (! defined($val)) {
        $val = '';
    }
    $self->{'input'} = $val;

    return $self;
}

sub get
{
    my $self = shift;
    my $len = shift || 1;

    if ($len > length($self->{'input'}) - $self->{'pos'}) {
        $len = length($self->{'input'}) - $self->{'pos'};
    }
    my $str = substr($self->{'input'}, $self->{'pos'}, $len);
    $self->{'pos'} += $len;
    if ($self->{'pos'} > length($self->{'input'})) {
        $self->{'pos'} = length($self->{'input'}) + 1;
    }
    return $str;
}

1;
