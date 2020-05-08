#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::Logger - a Perl package implementing a logger.
#

package Nextis::Logger;

use strict;
use Carp;
use IO::Handle;

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

my $levels = {
    'DEBUG' => 0,
    'NOTICE' => 1,
    'WARNING' => 2,
    'ERROR' => 3,
    'CRITICAL' => 4,
};

sub _make_empty_out_map
{
}

# Create a new Logger.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'prefix'} = undef;
    $self->{'out_map'} = undef;
    bless($self, $class);

    $self->reset();
    my $config = shift;
    if (defined($config)) {
        $self->set_config($config);
    }

    return $self;
}

# Reset the logger.
sub reset
{
    my $self = shift;

    my $out_map = [];
    for my $level (keys %{$levels}) {
        $out_map->[$levels->{$level}] = [];
    }
    $self->{'out_map'} = $out_map;
    $self->{'prefix'} = '';
}

# Rename all current outputs
sub rotate_output
{
    my $self = shift;

    my @t = localtime();
    my $cur_date = sprintf("%04d%02d%02d_%02d%02d%02d",
                           $t[5] + 1900, $t[4] + 1, $t[3],
                           @t[2,1,0]);
    for my $level_files (@{$self->{'out_map'}}) {
        for my $filename (@{$level_files}) {
            next if ($filename eq 'STDOUT' || $filename eq 'STDERR');
            rename($filename, "$filename.$cur_date");
        }
    }
}

# Set the prefix used in logging.
sub set_prefix
{
    my $self = shift;
    my $prefix = shift;

    if (defined($prefix) && $prefix ne '') {
        $self->{'prefix'} = ' ' . $prefix;
    } else {
        $self->{'prefix'} = '';
    }
}

# Add output to a file for the given levels.
sub add_output
{
    my $self = shift;
    my $filename = shift;
    my @levels = @_;

    for my $level (@levels) {
        my $level_num = 0;
        if ($level =~ /^\d+$/) {
            $level_num = $level;
        } elsif (exists($levels->{$level})) {
            $level_num = $levels->{$level};
        } else {
            next;
        }
        push @{$self->{'out_map'}->[$level_num]}, $filename;
    }
}

# Add a configuration from a hash containing the configuration
# section.
sub set_config
{
    my $self = shift;
    my $config = shift;

    for my $name (keys %{$config}) {
        if ($name eq 'prefix') {
            $self->set_prefix($config->{$name});
            next;
        }

        next if ($name !~ /^output\s+(.*)$/);
        my $filename = $1;

        $filename =~ s/^\s+//;
        $filename =~ s/\s+$//;
        my @levels = split(/\s*,\s*/, $config->{$name});
        $self->add_output($filename, @levels);
    }
}

sub _get_stdout
{
    my $self = shift;

    my $io = new IO::Handle();
    if ($io->fdopen(fileno(STDOUT), "w")) {
        $io->autoflush(1);
        return $io;
    }

    print STDERR "WARNING: can't open stdout for logging\n";
    return \&STDOUT;
}

sub _get_stderr
{
    my $self = shift;

    my $io = new IO::Handle;
    if ($io->fdopen(fileno(STDERR), "w")) {
        $io->autoflush(1);
        return $io;
    }

    print STDERR "WARNING: can't open stderr for logging\n";
    return \&STDERR;
}


# Log a message.
sub log
{
    my $self = shift;
    my $level = shift;
    my $msg = shift;

    # if only level was given, assume it's the message instead
    if (! defined($msg)) {
        return unless defined($level);
        $msg = $level;
        $level = undef;
    }

    # if no level was given, assume NOTICE
    if (! defined($level)) {
        $level = $levels->{'NOTICE'};
    }

    # read the numeric level from the table if necessary
    if ($level =~ /[^\d]/) {
        if (! exists($levels->{$level})) {
            $self->log('CRITICAL', "log: bad log level '$level', using 'NOTICE'");
            $level = $levels->{'NOTICE'};
        } else {
            $level = $levels->{$level};
        }
    }
    if ($level > $levels->{'CRITICAL'}) {
        $level = $levels->{'CRITICAL'};
    }

    my @t = localtime();
    my $date = sprintf("%02d/%02d/%04d %2d:%02d:%02d",
                       $t[3], $t[4] + 1, $t[5] + 1900, @t[2,1,0]);

    for my $file (@{$self->{'out_map'}->[$level]}) {
        my $fh;
        if ($file eq 'STDOUT') {
            $fh = $self->_get_stdout();
        } elsif ($file eq 'STDERR') {
            $fh = $self->_get_stderr();
        } else {
            $fh = undef;
            if (! open($fh, '>>', $file)) {
                $fh = $self->_get_stderr();
            }
        }
        if ($msg =~ /\n/) {
            my @msg = split(/\n/, $msg);
            for my $m (@msg) {
                print $fh "[$date$self->{'prefix'}] $m\n";
            }
        } else {
            print $fh "[$date$self->{'prefix'}] $msg\n";
        }
        close($fh);
    }
}
