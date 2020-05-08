#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CQStatLogger - a Perl package to log CQ daemon statistics.
#

package Nextis::CQStatLogger;

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

# Create a new [<cc>]Nextis::CQStatLogger[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'filename_template'} = '';
    $self->{'filename_template_vars'} = {};
    $self->{'last_write'} = undef;
    $self->{'fh'} = undef;
    bless($self, $class);

    return $self;
}

sub _get_current_filename
{
    my $self = shift;
    
    my @time = localtime();
    my $vars = {
        'hour' => sprintf("%02d", $time[2]),
        'minute' => sprintf("%02d", $time[1]),
        'second' => sprintf("%02d", $time[0]),
        'day' => sprintf("%02d", $time[3]),
        'month' => sprintf("%02d", $time[4] + 1),
        'year' => sprintf("%04d", $time[5] + 1900),
    };
    for my $name (keys %{$self->{'filename_template_vars'}}) {
        $vars->{$name} = $self->{'filename_template_vars'}->{$name};
    }

    my $filename = $self->{'filename_template'};
    $filename =~ s/\$\{([A-Za-z0-9_]+)\}/defined($vars->{$1}) ? $vars->{$1} : ''/ge;
    return $filename;
}

sub set_filename_template
{
    my $self = shift;
    my $template = shift;
    my $vars = shift;

    $self->{'filename_template'} = $template;
    $self->{'filename_template_vars'} = $vars;
    return 1;
}

sub open
{
    my $self = shift;

    my $filename = $self->_get_current_filename();

    my $fh = undef;
    if (! open($fh, '>>', $filename)) {
        return undef;
    }
    $self->{'fh'} = $fh;
    my $old = select($fh); $| = 1; select($old);
    return 1;
}

sub _escape_data
{
    my $data = shift;

    return '' unless defined($data);
    $data =~ s/([^A-Za-z0-9_])/sprintf("%%%02x", ord($1))/ge;
    return $data;
}

sub log
{
    my $self = shift;
    my $type = shift;
    my @data = @_;

    return undef unless defined($self->{'fh'});

    my $ts = time();

    # check if day changed, reopen log if yes
    if ($self->{'last_write'}) {
        my @old = localtime($self->{'last_write'});
        my @cur = localtime($ts);
        if ($old[3] != $cur[3]) {
            $self->close();
            $self->open();
        }
    }

    my $fh = $self->{'fh'};
    print $fh "$ts:$type:" . join(',', map { _escape_data($_) } @data) . "\n";
    $self->{'last_write'} = $ts;
    return 1;
}

sub close
{
    my $self = shift;

    return undef unless defined($self->{'fh'});
    my $ret = close($self->{'fh'});
    $self->{'fh'} = undef;
    return $ret;
}

1;
