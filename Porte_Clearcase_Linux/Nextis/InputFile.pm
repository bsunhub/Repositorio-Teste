#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::InputFile - a Perl package to read from files.
#

package Nextis::InputFile;

use strict;

use IO::File;

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
    bless($self, $class);

    my $val = shift || undef;
    if (ref($val) eq '') {
        $val = new IO::File($val, "r");
        return undef unless ($val);
    }
    $self->{'input'} = $val;

    return $self;
}

sub get
{
    my $self = shift;
    my $len = shift || 1;

    my $str = undef;
    if (read($self->{'input'}, $str, $len) <= 0) {
        return undef;
    }
    return $str;
}

1;
