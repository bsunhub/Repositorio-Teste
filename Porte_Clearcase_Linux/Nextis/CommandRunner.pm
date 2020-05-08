#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::CommandRunner - a Perl package to run commands.
#

package Nextis::CommandRunner;

#
# Usage example:
#
# [<code>]
# my $runner = new Nextis::CommandRunner('ls ${path}');
# $runner->run({ 'path' => '/' });
# $runner->run({ 'path' => './test' });
# [</code>]
#

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

# Create a new [<cc>]Nextis::CommandRunner[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'args'} = [];
    $self->{'data'} = [];
    $self->{'command'} = undef;
    $self->{'dont_parse'} = undef;
    $self->{'cmdline'} = undef;
    $self->{'exit_code'} = undef;
    $self->{'termination_status'} = undef;
    $self->{'output'} = undef;
    $self->{'logger'} = undef;
    $self->{'logger_level'} = undef;

    bless($self, $class);

    my $cmd = shift;
    my $dont_parse = shift;
    if (defined($cmd)) {
        $self->set_command($cmd, $dont_parse);
    }

    return $self;
}

sub _arg_unescape
{
    my $self = shift;
    my $str = shift;

    my $stuff = {
        '"' => '"',
        '\\' => '\\',
        'n' => "\n",
        'r' => "\r",
        't' => "\t",
    };

    my $out = '';
    while ($str =~ s{^(.*?)\\(.)}{
        $out .= $1;
        $out .= $stuff->{$2} || $2;
        '';
    }ge) {}
    $out .= $str;
    return $out;
}

sub set_logger
{
    my $self = shift;
    my $logger = shift;
    my $logger_level = shift;

    $self->{'logger'} = $logger;
    $self->{'logger_level'} = $logger_level;
}

sub set_command
{
    my $self = shift;
    my $command = shift;
    my $dont_parse = shift;

    $self->{'dont_parse'} = $dont_parse || 0;
    $self->{'command'} = $command;
    return 1 if ($self->{'dont_parse'});

    # parse command line
    $self->{'args'} = [];
    while (42) {
        my $done = 1;

        $command =~ s/^\s+//;

        if ($command =~ s/^\"((?:\\\"|[^\"])*)\"\s*//) {
            push @{$self->{'args'}}, $self->_arg_unescape($1);
            $done = 0;
            next;
        }

        if ($command =~ s/^([^\s]+)\s*//) {
            push @{$self->{'args'}}, $self->_arg_unescape($1);
            $done = 0;
            next;
        }
        last if ($done);
    }

    return 1;
}

sub _to_backslashes
{
    my $str = shift;
    $str =~ s|/|\\|g;
    return $str;
}

sub _to_double_backslashes
{
    my $str = shift;
    $str =~ s|/|\\\\|g;
    return $str;
}

sub _to_normalslashes
{
    my $str = shift;
    $str =~ s|\\|/|g;
    return $str;
}

sub _to_replace
{
    my $str = shift;
    my $re = shift;
    my $replacement = shift;

    eval("\$str =~ s|$re|$replacement|g;");
    #$str =~ s|$re|$replacement|g;
    return $str;
}

sub _debug_log
{
    my $str = shift;

    my $fh = undef;
    if (open($fh, '>>', 'log.xxx')) {
        print $fh "$str\n";
        close($fh);
    }
}

sub _prepare_arg
{
    my $self = shift;
    my $arg = shift;
    my $data = shift;

    $arg = '' unless (defined($arg));
    $arg =~ s/\$\{([A-Za-z0-9_]+)\}/$data->{$1} || ''/ge;
    $arg =~ s/\$\\\{([A-Za-z0-9_]+)\}/_to_backslashes($data->{$1} || '')/ge;
    $arg =~ s/\$\\\\\{([A-Za-z0-9_]+)\}/_to_double_backslashes($data->{$1} || '')/ge;
    $arg =~ s/\$\/{([A-Za-z0-9_]+)\}/_to_normalslashes($data->{$1} || '')/ge;
    #$arg =~ s/\\/\\\\/g;
    $arg =~ s/\"/\\\"/g;

    return $arg;
}

# Run the command with the given data replaced inside the arguments.
# Return: 1 if the command was run successfully (but might have
# terminated with an error code); 0 if the command could be run but
# was terminated by a signal or core dump; or undef if the command
# couldn't be run.
sub run
{
    my $self = shift;
    my $data = shift;
    my $redirect_stderr = shift;

    # prepare the command line with the given data
    my $cmdline;
    my $ok = eval {
        if (! $self->{'dont_parse'}) {
            my $num_args = scalar(@{$self->{'args'}});
            $cmdline = join(' ',
                            $self->_prepare_arg($self->{'args'}->[0], $data),
                            map({ '"' . $self->_prepare_arg($_, $data) . '"' }
                                @{$self->{'args'}}[1..$num_args-1]));
        } else {
            $cmdline = $self->{'command'};
            $cmdline =~ s/\$\{([A-Za-z0-9_]+)\}/$data->{$1} || ''/ge;
            $cmdline =~ s/\$\\\\\{([A-Za-z0-9_]+)\}/_to_double_backslashes($data->{$1} || '')/ge;
            $cmdline =~ s/\$\\\{([A-Za-z0-9_]+)\}/_to_backslashes($data->{$1} || '')/ge;
            $cmdline =~ s/\$\/\{([A-Za-z0-9_]+)\}/_to_normalslashes($data->{$1} || '')/ge;
            $cmdline =~ s/\$s\{([A-Za-z0-9_]+)\|([^\|]+)\|([^\|]+)\}/_to_replace($data->{$1}, $2, $3)/ge;
        }
        if ($redirect_stderr) {
            $cmdline .= ' 2>&1';
        }
        1;
    };
    if (! $ok) {
        #_debug_log("failed running: $@");
        return undef;
    }

    $self->{'cmdline'} = $cmdline;

    # run command and collect output
    my $failed = undef;
    if ($self->{'logger'}) {
        $self->{'logger'}->log($self->{'logger_level'}, "CommandRunner: running '$cmdline'");
    }
    #_debug_log("RUNNING '$cmdline'");
    if (! open(INPUT, "$cmdline |")) {
        $self->{'output'} = '';
        $self->{'exit_code'} = '';
        $self->{'termination_status'} = '';
            return undef;
    }
    $self->{'output'} = '';
    while (<INPUT>) {
        $self->{'output'} .= $_;
    }
    if (! close(INPUT)) {
        #$failed = 1;
    }
    my $cmd_status = $?;

    # read the exit code
    $self->{'exit_code'} = $cmd_status >> 8;
    $self->{'termination_status'} = $cmd_status & 0xff;

    return undef if ($failed);
    return ($self->{'termination_status'} == 0) ? 1 : 0;
}

sub command
{
    my $self = shift;

    return $self->{'command'};
}

sub cmdline
{
    my $self = shift;

    return $self->{'cmdline'};
}

sub output
{
    my $self = shift;

    return $self->{'output'};
}

sub exit_code
{
    my $self = shift;

    return $self->{'exit_code'};
}

sub termination_status
{
    my $self = shift;

    return $self->{'termination_status'};
}

1;
