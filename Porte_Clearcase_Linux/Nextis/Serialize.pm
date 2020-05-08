#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Serialize - a Perl package to serialize and deserialize data.
#

package Nextis::Serialize;

# This package handles the serialization and deserialization of the
# data transmitted between the engine client and server.

use strict;
use Carp;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw(&serialize &deserialize &escape_string &unescape_string);
}

# Return the escaped version of the given string.
sub escape_string
{
    my $str = shift;

    $str =~ s/\\/\\\\/g;
    $str =~ s[([\x00-\x1f])]{ "\\x" . sprintf("%02x", ord($1)) }eg;
    $str =~ s[([\x80-\xff])]{ "\\x" . sprintf("%02x", ord($1)) }eg;
    return $str;
};

# Returns the original string escaped with [<cc>]escape_string()[</cc>].
sub unescape_string
{
    my $str = shift;

    $str =~ s[\\x([0-9a-fA-F]{2})]{ chr(hex($1)) }eg;
    $str =~ s/\\\\/\\/g;
    return $str;
};

# Serialize the variable [<cc>]$var[</cc>] and return the resulting
# string.  Unknown objects referenced by the variable must be
# serialized by the function [<cc>]$ser_fnc[</cc>], which is called
# with two parameters: [<cc>]$ser_ctx[</cc>] and the object to be
# serialized.
sub serialize
{
    my $var = shift;
    my $ser_fnc = shift;
    my $ser_ctx = shift;

    for (ref($var)) {
        /^$/ && do {
            if (! defined($var)) { return 'UNDEF:0()'; }
            my $v = escape_string($var);
            my $len = length($v);
            return "STR:$len($v)";
        };

        /^SCALAR$/ && do {
            my $r = serialize(${$var});
            my $len = length($r);
            return "SCALAR:$len($r)";
        };

        /^REF$/ && do {
            my $r = serialize(${$var});
            my $len = length($r);
            return "REF:$len($r)";
        };

        /^ARRAY$/ && do {
            my $r = '';
            foreach (@{$var}) { $r .= serialize($_); }
            my $len = length($r);
            return "ARRAY:$len($r)";
        };

        /^HASH$/ && do {
            my $r = '';
            foreach my $k (keys %{$var}) {
                $r .= serialize($k);
                $r .= serialize($var->{$k});
            }
            my $len = length($r);
            return "HASH:$len($r)";
        };

        /^Nextis::CQObject$/ && do {
            my $r = $var->nx_name() . '.' . $var->nx_id();
            my $len = length($r);
            return "OBJ:$len($r)";
        };

        if (ref($ser_fnc) eq 'CODE') {
            return $ser_fnc->($ser_ctx, $var);
        }
        carp "Bad type to serialize: '" . ref($var) . "'";
    }

    return undef;
}

# De-serialize the string [<cc>]$str[</cc>] and return the resulting
# variable.  Unknown objects in the string must be de-serialized by
# the function [<cc>]$des_fnc[</cc>], which is called with two
# parameters: [<cc>]$des_ctx[</cc>] and the string to be
# de-serialized.
sub deserialize
{
    my $str = shift;
    my $des_fnc = shift;
    my $des_ctx = shift;

    if ($str !~ /^([A-Z]+):([0-9]+)\((.*)\)$/) {
        carp "Bad string to deserialize: '$str'";
        return undef;
    }
    my ($type, $len, $val) = ($1, $2, $3);

    if ($len != length($val)) {
        carp "Bad length deserializing string '$str'";
        return undef;
    }

    for ($type) {
        /^OBJ$/ && do {
            if (ref($des_fnc) eq 'CODE') {
                return $des_fnc->($des_ctx, $val);
            }
            return "<OBJECT:$val>";
        };

        /^UNDEF$/ && do { return undef; };

        /^STR$/ && do { return unescape_string($val); };

        /^SCALAR$/ && do {
            my $ret = deserialize($val);
            return \$ret;
        };

        /^REF$/ && do {
            my $ret = deserialize($val);
            return \$ret;
        };

        /^ARRAY$/ && do {
            my @ret;
            while ($val =~ s/^([A-Z]+):([0-9]+)//) {
                my ($type, $len) = ($1, $2);
                my $x = substr($val, 1, $len);
                push(@ret, deserialize("$type:$len($x)"));
                $val = substr($val, $len+2);
            }
            return \@ret;
        };

        /^HASH$/ && do {
            my %ret;
            my ($type, $len, $x, $k, $v);

            while (42) {
                last if ($val !~ s/^([A-Z]+):([0-9]+)//);
                ($type, $len) = ($1, $2);
                $x = substr($val, 1, $len);
                $k = deserialize("$type:$len($x)");
                $val = substr($val, $len+2);

                last if ($val !~ s/^([A-Z]+):([0-9]+)//);
                ($type, $len) = ($1, $2);
                $x = substr($val, 1, $len);
                $v = deserialize("$type:$len($x)");
                $val = substr($val, $len+2);

                $ret{$k} = $v;
            }
            return \%ret;
        };

        carp "Bad type to deserialize in '$str'";
    }
    return undef;
}

1;
