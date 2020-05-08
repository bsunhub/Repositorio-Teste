#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::Config - a Perl package to read command line arguments.
#

package Nextis::CommandLine;

# This package reads command line arguments.

use strict;
use Carp;

our $AUTOLOAD;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(parse_cmdline);
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}


sub cmdline_error
{
    my $arg = shift;
    my $opt_names = shift;

    # check if we expected a value
    for my $opt_name (@{$opt_names}) {
        next unless ($opt_name =~ /=$/);
        my $name = $opt_name;
        $name =~ s/=$//;
        if ($arg eq $name) {
            print STDERR "$0: option '$arg' expects a value.\n";
            return;
        }
    }

    print STDERR "$0: unknown option '$arg'\n";
}

# Parse the command line, return a reference to the options hash.
sub parse_cmdline
{
    my $args = shift;
    my $opt_names = shift;

    my $opts = { '_' => [] };
    for (my $i = 0; $i < scalar(@{$args}); $i++) {
        my $arg = $args->[$i];

        # non-options (e.g. filename arguments)
        if ($arg !~ /^-/) {
            push @{$opts->{'_'}}, $arg;
            next;
        }
        
        # long options with values
        if ($arg =~ /^(--[^=]+=)(.*)$/) {
            my $arg_name = $1;
            my $arg_value = $2;
            my $found = 0;
            for my $opt_name (@{$opt_names}) {
                if ($opt_name eq $arg_name) {
                    my $name = $opt_name;
                    $name =~ s/^--(.*)=$/$1/;
                    $opts->{$name} = $arg_value;
                    $found = 1;
                    last;
                }
            }
            if (! $found) {
                cmdline_error($arg, $opt_names);
                return undef;
            }
            next;
        }

        # long options with no values
        if ($arg =~ /^(--.*)$/) {
            my $found = 0;
            for my $opt_name (@{$opt_names}) {
                if ($arg eq $opt_name) {
                    my $name = $opt_name;
                    $name =~ s/^--//;
                    $opts->{$name}++;
                    $found = 1;
                    last;
                }
            }
            if (! $found) {
                cmdline_error($arg, $opt_names);
                return undef;
            }
            next;
        }

        # short options
        if ($arg =~ /^(-.*)$/) {
            my $found = 0;
            for my $opt_name (@{$opt_names}) {
                if ($arg eq $opt_name) {
                    my $name = $opt_name;
                    $name =~ s/^-(.*)$/$1/;
                    $opts->{$name}++;
                    $found = 1;
                    last;
                }
                if ($opt_name =~ /^\Q$arg\E=/) {
                    my $name = $opt_name;
                    $name =~ s/^-(.*)=/$1/;
                    if ($i+1 >= scalar(@{$args})) {
                        cmdline_error($arg, $opt_names);
                        return undef;
                    }
                    $opts->{$name} = $args->[++$i];
                    $found = 1;
                    last;
                }
            }
            if (! $found) {
                cmdline_error($arg, $opt_names);
                return undef;
            }
            next;
        }
    }

    return $opts;
}

1;

