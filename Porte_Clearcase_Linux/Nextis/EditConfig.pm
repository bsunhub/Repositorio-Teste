#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::EditConfig - a Perl package to edit configuration files.
#

package Nextis::EditConfig;

# ***********************************************************************
# ***********************************************************************
# ** WARNING                                                           **
# **                                                                   **
# ** This package assumes that each section appears only once in a     **
# ** config file.                                                      **
# ***********************************************************************
# ***********************************************************************

use strict;
use Carp;
use Data::Dumper;

our $AUTOLOAD;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&ECFLAGS_ADD_REPLACE
                      &ECFLAGS_ADD_INSERT
                      &ECFLAGS_POS_APPEND
                      &ECFLAGS_POS_PREPEND
                      &ECFLAGS_POS_INDEX);
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# flag bits: IIIIIIIIPPA
# where:
#  A        = add (0=replace, 1=insert)
#  PP       = pos (0=append, 1=prepend, 2=specify index)
#  IIIIIIII = pos index (if PP=2): position where to insert
sub ECFLAGS_ADD_REPLACE  { 0<<0 }
sub ECFLAGS_ADD_INSERT   { 1<<0 }
sub ECFLAGS_POS_APPEND   { 0<<1 }
sub ECFLAGS_POS_PREPEND  { 1<<1 }
sub ECFLAGS_POS_INDEX    { my $i = shift; return (2<<1) | (($i&0xff)<<3); }

# Create a new [<cc>]EditConfig[</cc>] object.  If [<cc>]$filename[</cc>]
# is given (and not [<cc>]undef[</cc>]), try to read it as a config
# file, and return [<cc>]undef[</cc>] on error.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $filename = shift;

    $self->{'config'} = [];
    bless($self, $class);

    if (defined($filename) && $filename) {
        return undef unless ($self->read($filename));
    }

    return $self;
}

sub _read_file
{
    my $self = shift;
    my $filename = shift;
    my $lines = shift;

    my $sect = '__MAIN__';
    my $line_num = 0;

    for (@{$lines}) {
        chomp;
        my $line = $_;

        push @{$self->{'config'}}, $line;
    }

    return 1;
};

# Read the configuration from file [<cc>]$filename[</cc>].
sub read
{
    my $self = shift;
    my $filename = shift;

    my $fh;
    if (! open($fh, '<', $filename)) {
        return undef;
    }
    my @lines = <$fh>;
    close($fh);

    return $self->_read_file($filename, \@lines);
}

# Read the configuration to file [<cc>]$filename[</cc>].
sub write
{
    my $self = shift;
    my $filename = shift;

    my $fh;
    if (! open($fh, '>', $filename)) {
        return undef;
    }
    for my $line (@{$self->{'config'}}) {
        print $fh "$line\n";
    }
    close($fh);

    return 1;
}

# Return the line number of the start of the given section, or
# [<cc>]undef[</cc>] if the section is not found.
sub _find_section
{
    my $self = shift;
    my $section = shift;

    for my $i (0..scalar(@{$self->{'config'}})-1) {
        if ($self->{'config'}->[$i] =~ /^\s*\[\s*\Q$section\E\s*\]/) {
            return $i;
        }
    }
    return undef;
}

# Return the index of the last non-empty line of the given section. 
sub _find_section_end
{
    my $self = shift;
    my $section = shift;

    my $end_sect_line = $self->_find_section($section);
    return undef unless defined($end_sect_line);

    $end_sect_line++; # skip [section] line
    while ($end_sect_line < scalar(@{$self->{'config'}})) {
        if ($self->{'config'}->[$end_sect_line] =~ /^\s*\[/) {
            while ($self->{'config'}->[$end_sect_line-1] =~ /^\s*$/) {
                $end_sect_line--; # backup blank line
            }
            return $end_sect_line - 1;
        }
        $end_sect_line++;
    }
    return $end_sect_line - 1;
}

# Return the line number of the given option in the given section, or
# [<cc>]undef[</cc>] if the option or section are not found.
sub _find_option
{
    my $self = shift;
    my $section = shift;
    my $name = shift;

    my $i = $self->_find_section($section);
    return undef unless defined($i);

    $i++; # skip [section] line
    while ($i < scalar(@{$self->{'config'}})) {
        my $line = $self->{'config'}->[$i];
        if ($line =~ /^\s*\Q$name\E\s*=/) {
            return $i;
        }
        if ($line =~ /^\s*\[/) {
            return undef;
        }
        $i++;
    }
    return undef;
}

# Insert a new option in the configuration in the given section with
# the given name and value. The [<cc>]$flags[</cc>] are a binary-or
# combination of the ECFLAGS_xxx values.
sub insert_option
{
    my $self = shift;
    my $section = shift;
    my $name = shift;
    my $value = shift;
    my $flags = shift;

    my $new_str = "$name = $value";

    # extract behaviour from flags
    $flags = 0 unless defined($flags);
    my $add_spec = $flags & 1;
    my $pos_spec = ($flags >> 1) & 3;
    my $pos_index = ($flags >> 3) & 0xff;

    # replace
    if ($add_spec == 0) {
        my $line = $self->_find_option($section, $name);
        if (defined($line)) {
            $self->{'config'}->[$line] = $new_str;
            return 1;
        }
    }

    # insert
    my $sect_line = $self->_find_section($section);
    
    # -- must create the section
    if (! defined($sect_line)) {
        push @{$self->{'config'}}, "";
        push @{$self->{'config'}}, "[$section]";
        push @{$self->{'config'}}, $new_str;
        return 1;
    }

    $sect_line++; # skip [section] line

    # -- insert at end (append)
    if ($pos_spec == 0) {
        my $end_sect_line = $self->_find_section_end($section);
        splice(@{$self->{'config'}}, $end_sect_line+1, 0, $new_str);
        return 1;
    }

    # -- insert at beginning (prepend)
    if ($pos_spec == 1) {
        splice(@{$self->{'config'}}, $sect_line, 0, $new_str);
        return 1;
    }

    # -- insert at specified position
    if ($pos_spec == 2) {
        my $end_sect_line = $self->_find_section_end($section);
        if ($pos_index > $end_sect_line - $sect_line + 1) {
            die "Position $pos_index is outside of section [$section]";
        }
        splice(@{$self->{'config'}}, $sect_line + $pos_index, 0, $new_str);
        return 1;
    }

    die "Nothing to do with flags '$flags'";
}

# Return 1 if the given section exists, 0 if not.
sub section_exists
{
    my $self = shift;
    my $section = shift;

    my $line = $self->_find_section($section);
    return (defined($line)) ? 1 : 0;
}

# Return 1 if the given option of the given section exists, 0 if not.
sub option_exists
{
    my $self = shift;
    my $section = shift;
    my $name = shift;

    my $line = $self->_find_option($section, $name);
    return (defined($line)) ? 1 : 0;
}

# Remove a section from the file
sub remove_section
{
    my $self = shift;
    my $section = shift;

    my $start_line = $self->_find_section($section);
    my $last_line = $self->_find_section_end($section);

    return $self->remove_lines($start_line, $last_line - $start_line + 1);
}

# Insert the given lines at the specified position in the file.
sub insert_lines
{
    my $self = shift;
    my $line_num = shift;
    my $lines = shift;

    splice(@{$self->{'config'}}, $line_num, 0, @{$lines});
    return 1;
}

# Append the given lines at the end of the file.
sub append_lines
{
    my $self = shift;
    my $lines = shift;

    return $self->insert_lines(scalar(@{$self->{'config'}}), $lines);
}

# Insert the given lines at the beginning of the file.
sub prepend_lines
{
    my $self = shift;
    my $lines = shift;

    return $self->insert_lines(0, $lines);
}

# Remove from the file the given number of lines starting at the given
# line.
sub remove_lines
{
    my $self = shift;
    my $line_num = shift;
    my $num_lines = shift;

    splice(@{$self->{'config'}}, $line_num, $num_lines);
    return 1;
}

# Remove double empty lines and empty lines at the end of file. 
sub tidy
{
    my $self = shift;

    my $i = 0;

    # remove double empty lines
    my $last_was_empty = 0;
    while ($i < scalar(@{$self->{'config'}})) {
        if ($self->{'config'}->[$i] =~ /^\s*$/) {
            if ($last_was_empty) {
                splice(@{$self->{'config'}}, $i, 1);
                next;
            } else {
                $last_was_empty = 1;
            }
        } else {
            $last_was_empty = 0;
        }
        $i++;
    }

    # remove empty lines at the end of file
    $i = scalar(@{$self->{'config'}}) - 1;
    while ($i > 0) {
        if ($self->{'config'}->[$i] =~ /^\s*$/) {
            splice(@{$self->{'config'}}, $i, 1);
        } else {
            last;
        }            
        $i--;
    }

    return 1;
}

1;
