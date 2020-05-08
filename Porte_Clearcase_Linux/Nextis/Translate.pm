#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Translate - a Perl package to translate text.
#

package Nextis::Translate;

# This package is used to translate text used in the engine.

use strict;
use Carp;
use Data::Dumper;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = ();
}

# Create a new translation object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $lang = shift;

    $self->{'string_map'} = {};
    $self->{'message_map'} = [];
    $self->{'field_map'} = {};
    $self->{'colorize'} = 0;
    bless($self, $class);

    return $self;
}

sub colorize
{
    my $self = shift;
    my $colorize = shift;

    $colorize = 1 unless defined($colorize);
    $self->{'colorize'} = $colorize;
    return 1;
}

# ------------------------------------------------------------
# --- messages -----------------------------------------------

# Add one or more mappings to the message mapping table.
# [<code>]
# %map = (
#   $regexp => $replace_value,
#   ...
# );
# [</code>]
sub add_message_mapping
{
    my $self = shift;
    my %map = @_;

    my @errors = ();

    foreach (keys %map) {
        my $in = $_;

        my ($re, $err);
        eval {
            $re = qr/$in/s;
        };
        if ($@) {
            $err = $@;
        }
        if ($err) {
            push @errors, $err;
        } else {
            push @{$self->{'message_map'}}, [ $in, $re, $map{$_} ];
        }
    }

    if (scalar(@errors) >= 1) {
        return \@errors;
    }
    return undef;
}

# Load message mappings from a file.
sub load_message_file
{
    my $self = shift;
    my $filename = shift;

    # read the file
    if (! open(INPUT,"<$filename")) {
        return undef;
    }
    my $save = $/;
    $/ = undef;
    my $file = <INPUT>;
    $/ = $save;
    close(INPUT);

    $file =~ s/^\s*\#.*$//mg;

    # parse the strings
    while ($file =~ s/\[\[\[(.*?)\|\|\|(.*?)\]\]\]//s) {
        my $in = $1;
        my $out = $2;
        $in =~ s/\n/\\s?/g;
        $out =~ s/\n/ /g;

        my $err = $self->add_message_mapping($in, $out);
        if ($err) {
            carp "bad regular expression in file $filename: $err->[0]";
        }
    }
    if ($file =~ /[^\s]/) {
        my $err = $file;
        $err =~ s/\r?\n/ /g;
        $err =~ s/^\s+//g;
        $err =~ s/\s+$//g;
        carp "bad translation file $filename near: '$err'";
        return $file;
    }
    return '';
}

# Translate a message given the current defined mappings.
sub translate_message
{
    my $self = shift;
    my $sect = shift;
    my $str = shift;
    my $error = shift;

    my $done = 0;
    for my $map (@{$self->{'message_map'}}) {
        my $in = $map->[0];
        my $re = $map->[1];
        my $out = $map->[2];
        $out =~ s/\//\\\//g;
        eval("\$done = 1 if (\$str =~ s/\$re/$out/);");
        if ($@) {
            my $err = $@;
            $error->($err) if (ref($error) eq 'CODE');
        }
        if ($done) {
            while ($str =~ s[CAMPO\(([^)]+)\)]{
                my $val = $1;
                my $ret = $self->translate_field($sect, $val);
                $ret = $val if ($ret eq '');
                $ret;
            }ge) { }
            return $str;
        }
    }
    return $str;
}

# ------------------------------------------------------------
# --- fields -------------------------------------------------

# Add a mapping to the field mapping table.
sub add_field_mapping
{
    my $self = shift;
    my $sect = shift;
    my $name = shift;
    my $val = shift;

    $self->{'field_map'}->{$sect} = {} unless exists($self->{'field_map'}->{$sect});
    $self->{'field_map'}->{$sect}->{$name} = $val;
    return 1;
}

# Load field mappings from a file.  Return [<cc>]1[</cc>] on success,
# [<cc>]undef[</cc>] on error.
sub load_field_file
{
    my $self = shift;
    my $filename = shift;
    my $skip_includes = shift;

    # read the file
    if (! open(INPUT, "<$filename")) {
        return undef;
    }
    my @lines = <INPUT>;
    close(INPUT);

    # parse it
    my $sect = '__MAIN__';
    my $line_num = 0;
    for (@lines) {
        chomp;
        my $line = $_;
        $line =~ s/^\s*\#.*$//;
        $line =~ s/\r$//;

        $line_num++;
        next if ($line =~ /^\s*$/);

        # include another config file
        if ($line =~ /^\s*\.include\s+\"(.*)\"\s*$/) {
            my $f = $1;

            next if $skip_includes;

            # prepend current file directory to file to include if it
            # is not absolute
            if ($f !~ /^\//) {
                my $d = $filename;
                $f = "$d/$f" if ($d =~ s|^(.*)/.*$|$1|);
            }
            if (! $self->load_field_file($f)) {
                carp "$filename:$line_num: include: can't read file '$f'";
            }
            next;
        }

        # new section
        if ($line =~ /^\s*\[([^\[\]=]+)\]\s*$/) {
            $sect = $1;
            next;
        }

        # new config
        if ($line =~ /^\s*([^=]+?)\s*=(.*)$/) {
            my $name = $1;
            my $val = $2;
            $val =~ s/^\s*(.*?)\s*$/$1/;
            $val =~ s/\\(.)/$1/g;
            $self->add_field_mapping($sect, $name, $val);
            next;
        }

        carp "$filename:$line_num: bad config line: '$line'";
    }

    return 1;
}

# Return a reference to an array with the names of the sections
# available for field translations.
sub get_field_sections
{
    my $self = shift;

    my @sect = sort keys %{$self->{'field_map'}};
    return \@sect;
}

# Return a reference to a hash with the field translations for a given
# section, or [<cc>]undef[</cc>] if the given section doesn't exist.
sub get_field_section
{
    my $self = shift;
    my $sect = shift;

    if (ref($self->{'field_map'}->{$sect}) eq 'HASH') {
        my %trans = %{$self->{'field_map'}->{$sect}};
        return \%trans;
    }
    return undef;
}

# Remove a section from the field translations.
sub remove_field_section
{
    my $self = shift;
    my $sect = shift;

    delete $self->{'field_map'}->{$sect};
    return 1;
}

my $color_translation = sub {
    my $color = shift;
    my $field = shift;

    return "<font color='$color'>$field</font>";
};

# Translate a field given the current field mapping table.
sub translate_field
{
    my $self = shift;
    my $sect = shift;
    my $field = shift;

    if (exists($self->{'field_map'}->{$sect})
        && exists($self->{'field_map'}->{$sect}->{$field})) {
        if ($self->{'colorize'} && ($sect !~ /\.trans_field$/)) {
            return $color_translation->('#30cfcf', $self->{'field_map'}->{$sect}->{$field});;
        }
        return $self->{'field_map'}->{$sect}->{$field};
    }

    $field =~ s/^<<(.*)>>$/$1/;
    return (($self->{'colorize'})
            ? $color_translation->('#ff30ff', $field)
            : $field);
}

# Return [<cc>]1[</cc>] if the field has a defined mapping,
# [<cc>]0[</cc>] if not.
sub field_has_translation
{
    my $self = shift;
    my $sect = shift;
    my $field = shift;

    if (exists($self->{'field_map'}->{$sect})
        && exists($self->{'field_map'}->{$sect}->{$field})) {
        return 1;
    }
    return 0;
}

# ------------------------------------------------------------
# --- strings ------------------------------------------------

# Add a string mapping to the string mapping table.
sub add_string_mapping
{
    my $self = shift;
    my $name = shift;
    my $val = shift;

    $self->{'string_map'}->{$name} = $val;
    return 1;
}

# Load string mappings from a file.
sub load_string_file
{
    my $self = shift;
    my $filename = shift;

    if (! open(INPUT, "<$filename")) {
        return undef;
    }

    while (<INPUT>) {
        chomp;
        s/\#.*$//;
        next if (/^\s*$/);
        my ($name, $val) = split(/\s*=\s*/, $_, 2);
        $self->add_string_mapping($name, $val);
    }
    close(INPUT);
    return 1;
}

# Get a string from the string mapping table.
sub get_string
{
    my $self = shift;
    my $code = shift;

    if (! exists($self->{'string_map'}->{$code})) {
        return "(bad string code: $code)";
    }
    return $self->{'string_map'}->{$code};
}

1;
