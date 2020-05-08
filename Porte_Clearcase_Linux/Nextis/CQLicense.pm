#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CQLicense - a Perl package to hold a license.
#

package Nextis::CQLicense;

use strict;
use Carp;
use Fcntl;
use Digest::MD5;
use MIME::Base64;
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

our $signature_key = 'Pantufas';

our $_make_cfg_signature = sub {
    my $key = shift;
    my $cfg = shift;

    my $md5 = new Digest::MD5();

    $md5->add("[[[[$key]]]]");
    for my $section (sort keys %{$cfg}) {
        next if ($section eq '__signature__');
        $md5->add("[[[[$section]]]]");
        for my $name (sort keys %{$cfg->{$section}}) {
            my $value = $cfg->{$section}->{$name};
            $value = '' unless (defined($value));
            $md5->add("[[[[(((($name))))(((($value))))]]]]");
            #print "ADD <$key> [$section] '$name' = '$value'\n";
        }
    }

    return $md5->hexdigest();
};

our $_check_cfg_signature = sub {
    my $key = shift;
    my $cfg = shift;

    my $signature = $_make_cfg_signature->($key, $cfg);
    if ($signature eq $cfg->{'__signature__'}->{'__signature__'}) {
        return 1;
    }

    return undef;
};

my $xor_str = sub {
    my $str = shift;
    my $val = shift;

    my $n = length($str);
    for (my $i = 0; $i < $n; $i++) {
        vec($str, $i, 8) ^= 0xaa;
    }
    return $str;
};

my $read_file = sub {
    my $filename = shift;
    my $do_xor = shift;

    # read file
    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        return undef;
    }
    binmode($fh);
    my $content = do {
        local $/ = undef;
        scalar(<$fh>);
    };
    close($fh);

    # de-XOR it
    if ($do_xor) {
        $content = $xor_str->($content, 42);
    }

    return $content;
};

my $write_file = sub {
    my $filename = shift;
    my $content = shift;
    my $do_xor = shift;

    # XOR it
    if ($do_xor) {
        $content = $xor_str->($content, 42);
    }

    # write file
    my $fh = undef;
    if (! open($fh, '>', $filename)) {
        return undef;
    }
    binmode($fh);
    print $fh $content;
    close($fh);

    return 1;
};

my $read_cfg = sub {
    my $filename = shift;
    my $do_xor = shift;

    my $cfg = {};
    my $num_errors = 0;

    my $file = $read_file->($filename, $do_xor);
    my @file = split(/\n/, $file);
    my $cur_sect = '__MAIN__';
    for my $l (@file) {
        chomp($l);
        $l =~ s/\r//g;
        $l =~ s/^\s+//;
        next if ($l eq '');
        next if ($l =~ /^\#/);
        if ($l =~ /^\[(.*)\]\s*$/) {
            $cur_sect = $1;
            next;
        }
        if ($l =~ /^\s*([^=]+?)\s*=(.*)$/) {
            my $name = $1;
            my $val = $2;
            if (! exists($cfg->{$cur_sect})) {
                $cfg->{$cur_sect} = {};
            }
            $name =~ s/^\s+//;
            $name =~ s/\s+$//;
            $val =~ s/^\s+//;
            $val =~ s/\s+$//;
            $cfg->{$cur_sect}->{$name} = $val;
            next;
        }
        $cfg->{'__ERRORS__'}->{"err$num_errors"} = "bad license line: '$l'";
        $num_errors++;
    }
    return $cfg;
};

my $write_cfg = sub {
    my $filename = shift;
    my $cfg = shift;
    my $do_xor = shift;

    my $content = '';
    for my $sect (sort keys %{$cfg}) {
        $content .= "\n[$sect]\n";
        for my $name (sort keys %{$cfg->{$sect}}) {
            my $val = $cfg->{$sect}->{$name};
            $val = '' unless (defined($val));
            $content .= "$name = $val\n";
        }
    }

    return $write_file->($filename, $content, $do_xor);
};

# Create a new [<cc>]CQLicense[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'data'} = undef;
    $self->{'signature'} = undef;
    $self->{'last_error'} = undef;
    bless($self, $class);

    my $filename = shift;
    if (defined($filename) && ! $self->read_and_check($filename)) {
        return undef;
    }

    return $self;
}

# Return the last error message.
sub last_error
{
    return shift->{'last_error'};
}

# Set the last error message to be returned by [<cc>]last_error[</cc>].
sub set_last_error
{
    my $self = shift;
    my $err = shift;

    return $self->{'last_error'} = $err;
}

sub get_value
{
    my $self = shift;
    my $section = shift;
    my $name = shift;

    if (! $self->{'data'}) {
        $self->set_last_error("No valid license");
        return undef;
    }

    if (! exists($self->{'data'}->{$section})
        || ! exists($self->{'data'}->{$section}->{$name})) {
        return '';
    }
    return $self->{'data'}->{$section}->{$name};
}

# Read a license file, checking if the license signature is valid.
sub read_and_check
{
    my $self = shift;
    my $filename = shift;

    my $cfg = $read_cfg->($filename, 1);
    if (! $cfg) {
        $self->set_last_error("Can't read '$filename': $!");
        return undef;
    }

    if (! $_check_cfg_signature->($signature_key, $cfg)) {
        $self->set_last_error("Bad license signature in '$filename'");
        return undef;
    }

    $self->{'data'} = $cfg;
    return 1;
}

# Read and sign a license file.
sub read_and_sign
{
    my $self = shift;
    my $filename = shift;

    my $cfg = $read_cfg->($filename, 0);
    if (! $cfg) {
        $self->set_last_error("Can't read '$filename': $!");
        return undef;
    }

    my $signature = $_make_cfg_signature->($signature_key, $cfg);
    $cfg->{'__signature__'}->{'__signature__'} = $signature;

    $self->{'data'} = $cfg;
    return 1;
}

# Write a license file.
sub write
{
    my $self = shift;
    my $filename = shift;

    return $write_cfg->($filename, $self->{'data'}, 1);
}

1;
