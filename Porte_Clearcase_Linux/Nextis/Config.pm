#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Config - a Perl package to read configuration files.
#

package Nextis::Config;

# This package reads and parses a configuration file.

use strict;
use Carp;
use Data::Dumper;

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

# Create a new [<cc>]Config[</cc>] object.  If [<cc>]$filename[</cc>]
# is given (and not [<cc>]undef[</cc>]), try to read it as a config
# file, and return [<cc>]undef[</cc>] on error.  If
# [<cc>]$interpolate[</cc>] is true, parse variables in the
# configuration values.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $filename = shift;
    my $interpolate = shift || 0;

    $self->{'config'} = { '**ORDER**' => [] };
    $self->{'interpolate'} = $interpolate;
    bless($self, $class);

    if (defined($filename) && $filename) {
        return undef unless ($self->read($filename));
    }

    return $self;
}

# Set the status of the interpolation of configuration values.  If
# true, variables will be interpolated in the configuration values.
sub interpolate
{
    my $self = shift;
    my $interpolate = shift;

    my $old_interpolate = $self->{'interpolate'};
    $self->{'interpolate'} = $interpolate if defined($interpolate);
    return $old_interpolate;
}

sub _interp_val
{
    my $self = shift;
    my $sect = shift;
    my $val = shift;

    $val =~ s[\${([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)}]{
        my $v = $self->get_value($1, $2);
        defined($v) ? $v : ''
        }eg;

    $val =~ s[\${([A-Za-z0-9_]+)}]{
        my $v = $self->get_value($sect, $1);
        defined($v) ? $v : ''
        }eg;
    return $val;
}

sub _add_option
{
    my $self = shift;
    my $sect = shift;
    my $name = shift;
    my $val = shift;

    $val =~ s/^\s*(.*)\s*$/$1/;
    if (! exists($self->{'config'}->{$sect})) {
        if (! grep { $_ eq $sect } @{$self->{'config'}->{'**ORDER**'}}) {
            push @{$self->{'config'}->{'**ORDER**'}}, $sect;
        }
        $self->{'config'}->{$sect} = { '**ORDER**' => [] };
    }
    $val = $self->_interp_val($sect, $val) if ($self->{'interpolate'});
    if (! grep { $_ eq $name } @{$self->{'config'}->{$sect}->{'**ORDER**'}}) {
        push @{$self->{'config'}->{$sect}->{'**ORDER**'}}, $name;
    }
    $self->{'config'}->{$sect}->{$name} = $val;
}

sub _parse_file
{
    my $self = shift;
    my $filename = shift;
    my $lines = shift;

    my $sect = '__MAIN__';
    my $line_num = 0;

    for (@{$lines}) {
        chomp;
        my $line = $_;
        $line =~ s/([^\\])\#.*$/$1/;
        $line =~ s/^\#.*$//;
        $line =~ s/\r$//;

        $line =~ s/\\\#/\#/g;

        $line_num++;
        next if ($line =~ /^\s*$/);

        # new section
        if ($line =~ /^\s*\[([^\[\]]+)\]\s*$/) {
            $sect = $1;
            if (! grep { $_ eq $sect } @{$self->{'config'}->{'**ORDER**'}}) {
                push @{$self->{'config'}->{'**ORDER**'}}, $sect;
            }
            next;
        }

        # include another config file
        if ($line =~ /^\s*\.include\s+\"(.*)\"\s*$/) {
            my $f = $1;

            # prepend current file directory to file to include if it
            # is not absolute
            if ($f !~ /^\//) {
                my $d = $filename;
                $f = "$d/$f" if ($d =~ s|^(.*)/.*$|$1|);
            }
            if (! $self->read($f)) {
                carp "$filename:$line_num: include: can't read file '$f'";
            }
            next;
        }

        # "option" = value
        if ($line =~ /^\s*(\"(?:[^\"]|\\\")*\")\s*=(.*)$/) {
            my $name = $1;
            my $val = $2;
            $self->_add_option($sect, $name, $val);
            next;
        }

        # option = value
        if ($line =~ /^\s*([^=]+?)\s*=(.*)$/) {
            my $name = $1;
            my $val = $2;
            $self->_add_option($sect, $name, $val);
            next;
        }

        carp "$filename:$line_num: bad config line: '$line'";
    }

    return 1;
};

# Read the configuration file [<cc>]$filename[</cc>].
sub read
{
    my $self = shift;
    my $filename = shift;

    if (! open(CFG, "<$filename")) {
        return undef;
    }
    my @lines = <CFG>;
    close(CFG);

    return $self->_parse_file($filename, \@lines);
}

# Return a reference to an array of names of the defined options in
# the configuration section [<cc>]$sect[</cc>].
sub get_section_option_names
{
    my $self = shift;
    my $sect = shift;

    return undef unless exists ($self->{'config'}->{$sect});
    return [ @{$self->{'config'}->{$sect}->{'**ORDER**'}} ];
}

# Return the value of the option [<cc>]$name[</cc>] in the section
# [<cc>]$sect[</cc>].
sub get_value
{
    my $self = shift;
    my $sect = shift;
    my $name = shift;

    return undef unless exists ($self->{'config'}->{$sect});
    return $self->{'config'}->{$sect}->{$name};
}

# Return a reference to an array of section names of the configuration.
sub get_section_names
{
    my $self = shift;

    return [ @{$self->{'config'}->{'**ORDER**'}} ];
}

# Return a hash with the options and values from the configuration
# section [<cc>]$sect[</cc>].
sub get_section
{
    my $self = shift;
    my $sect = shift;

    return undef unless exists ($self->{'config'}->{$sect});

    my %ret = %{$self->{'config'}->{$sect}};
    delete($ret{'**ORDER**'});
    return \%ret;
}

# Return 1 if the section named [<cc>]$sect[</cc>] exists in the
# configuration, undef otherwise.
sub section_exists
{
    my $self = shift;
    my $sect = shift;

    return undef unless exists ($self->{'config'}->{$sect});
    return 1;
}

# ---------------------------------------------------------------------
# DEPRECATED stuff:

# Return a reference to an array of section names of the configuration.
# [<cc>]DEPRECATED[</cc>]: use [<cc>]get_section_names()[</cc>] instead.
sub get_sections
{
    my $self = shift;

    return $self->get_section_names();
}

# Return a reference to an array of names of the defined options in
# the configuration section [<cc>]$sect[</cc>].
# [<cc>]DEPRECATED[</cc>]: use [<cc>]get_section_option_names()[</cc>]
# instead.
sub get_values
{
    my $self = shift;
    my $sect = shift;

    return $self->get_section_option_names($sect);
}

1;
