#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::PasswordMan - a Perl package to manage password files for the engine.
#

package Nextis::PasswordMan;

# This package handles password files used in the engine server.

use strict;
use Digest::MD5;

# Generate a new id
my $gen_id = sub {
    return Digest::MD5::md5_base64(rand(1000000));
};

# Encrypt a password given a salt
my $crypt = sub {
    my $password = shift;
    my $salt = shift;

    my $x;
    if (! defined($salt) || length($salt) < 8) {
        $x = substr($gen_id->(), 0, 8);
    } else {
        $x = substr($salt, 0, 8);
    }
    return $x . Digest::MD5::md5_base64($x . $password);
};


# Create a new [<cc>]PasswordMan[</cc>] object.  If
# [<cc>]$pwd_file[</cc>] is given, read the password file from it, and
# return [<cc>]undef[</cc>] on error.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $pwd_file = shift || '';

    bless($self, $class);
    $self->{'pwd_file'} = $pwd_file;
    $self->{'users'} = {};

    if ($pwd_file) {
        return undef unless $self->read_password_file($pwd_file);
    }

    return $self;
}

# Add a new user to the password file.
sub add_user
{
    my $self = shift;
    my $username = shift;
    my $perms = shift;
    my $password = shift;

    $self->{'users'}->{$username} = [ $username, $perms, $crypt->($password) ];
}

# Add a new user to the password file with the password already hashed.
sub add_user_hashed_password
{
    my $self = shift;
    my $username = shift;
    my $perms = shift;
    my $hash_password = shift;

    $self->{'users'}->{$username} = [ $username, $perms, $hash_password ];
}

# Remove the user from the passaword file.
sub remove_user
{
    my $self = shift;
    my $username = shift;

    delete($self->{'users'}->{$username});
}

# Retrieve the hash entry for the username in the password file.
sub get_user
{
    my $self = shift;
    my $username = shift;

    return $self->{'users'}->{$username};
}

# Check if the username has the required permissions given in the
# bitmask [<cc>]$perms[</cc>].  Return [<cc>]1[</cc>] if the user has
# permissions, [<cc>]0[</cc>] if not, or [<cc>]undef[</cc>] if the
# user doesn't exist.
sub check_user_perms
{
    my $self = shift;
    my $username = shift;
    my $perms = shift;

    return undef unless exists($self->{'users'}->{$username});

    if (($self->{'users'}->{$username}->[1] & $perms) == $perms) {
        return 1;
    }
    return 0;
}

# Check the password of the username.  Return [<cc>]1[</cc>] if the
# password is good, [<cc>]0[</cc>] if not, or [<cc>]undef[</cc>]
# if the user doesn't exist.
sub check_user_password
{
    my $self = shift;
    my $username = shift;
    my $password = shift;

    return undef unless exists($self->{'users'}->{$username});

    my $x = $crypt->($password, $self->{'users'}->{$username}->[2]);
    if ($x eq $self->{'users'}->{$username}->[2]) {
        return 1;
    }
    return 0;
}

# Remove all users from the password file.
sub remove_all_users
{
    my $self = shift;

    $self->{'users'} = {};
}

# Read the given password file and merge the read entries with the
# current password file.  Users already presents will be overwritten.
sub merge_password_file
{
    my $self = shift;
    my $file = shift;

    if (! open(FILE, "<$file")) {
        return undef;
    }
    while (<FILE>) {
        chomp;
        my @l = split(/:/, $_, 3);
        next if (scalar(@l) != 3);
        $self->add_user_hashed_password($l[0], $l[1], $l[2]);
    }
    close(FILE);
    return 1;
}

# Read the given password file.
sub read_password_file
{
    my $self = shift;
    my $file = shift;

    $self->remove_all_users();
    return $self->merge_password_file($file);
}

# Write the password file to the given filename [<cc>]$file[</cc>].
sub write_password_file
{
    my $self = shift;
    my $file = shift;

    if (! open(FILE, ">$file")) {
        return undef;
    }
    for my $username (keys %{$self->{'users'}}) {
        my $u = $self->get_user($username);
        print FILE "$u->[0]:$u->[1]:$u->[2]\n";
    }
    close(FILE);
    return 1;
}

1;
