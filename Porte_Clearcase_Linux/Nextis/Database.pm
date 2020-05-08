#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Database - a Perl package for database access.
#

package Nextis::Database;

# This package is used for database access.
#
# Usage example:
#
# [<code>]
# my $db = new Nextis::Database({ 'host' => $host,
#                                 'port' => $port,  # optional
#                                 'user' => $user,
#                                 'password' => $password,
#                                 'database' => $database, });
# die "Can't connect to DB" unless $db;
# [</code>]
# or
# [<code>]
# my $db = new Nextis::Database();
# if (! $db->connect({ 'host' => $host,
#                      'port' => $port,  # optional
#                      'user' => $user,
#                      'password' => $password,
#                      'database' => $database, })) {
#   die "Can't connect to DB: " . $db->last_error();
# }
# [</code>]
# then
# [<code>]
# my $res = $db->query("SELECT * FROM table");
# my $l;
# while ($l = $db->fetch_array($res)) {
#   # process line $l
# }
# [</code>]

use strict;
use Carp;
use DBI;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&addslashes &db_check_number);
    %EXPORT_TAGS = ();
    @EXPORT_OK   = ();
}

# Create a new translation object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $db_conf = shift;

    $self->{'dbh'} = undef;
    $self->{'last_error'} = '';
    $self->{'pref'} = '';
    $self->{'tracer'} = undef;
    $self->{'connected'} = '';
    bless($self, $class);

    if (defined($db_conf)) {
        return undef unless $self->connect($db_conf);
    }

    return $self;
}

# Return 1 if the given string is a number (i.e., if it is not empty
# and contains only digits).
sub is_number
{
    my $self = shift;
    my $str = shift;

    return 0 if (! defined($str) || $str eq '');
    return 0 if ($str =~ /[^\d]/);
    return 1;
}

# Escape a value to be used in a query.
sub addslashes
{
    my $str = shift;

    return undef unless (defined($str));

    $str =~ s/\\/\\\\/g;
    $str =~ s/\'/\\\'/g;
    $str =~ s/\"/\\\"/g;
    return $str;
}

# Check if the given string is a number
sub db_check_number
{
    my $str = shift;

    return 0 unless defined($str);
    return 1 if ($str =~ /^\d+$/);
    return 0;
}

# Connect to the database.
sub connect
{
    my $self = shift;
    my $db_conf = shift;

    $self->{'pref'} = $db_conf->{'pref'} || '';

    my $conn_str = "dbi:mysql:database=$db_conf->{'database'}";
    $conn_str .= ";host=$db_conf->{'host'}" if exists($db_conf->{'host'});
    $conn_str .= ";port=$db_conf->{'port'}" if exists($db_conf->{'port'});
    $self->{'dbh'} = DBI->connect($conn_str,
                                  $db_conf->{'user'},
                                  $db_conf->{'password'});
    if (! $self->{'dbh'}) {
        $self->set_last_error($DBI::errstr);
        return undef;
    }
    $self->{'connected'} = 1;
    return $self->{'dbh'};
}

sub last_error
{
    my $self = shift;

    return $self->{'last_error'};
}

sub set_last_error
{
    my $self = shift;
    my $msg = shift;

    $self->{'last_error'} = $msg;
    return $msg;
}

sub connected
{
    my $self = shift;

    return $self->{'connected'};
}

# Set a tracer routine to be called every time a query is to be made.
# The query will be executed only if the tracer routine returns true.
sub set_tracer
{
    my $self = shift;
    my $tracer = shift;

    return undef unless (ref($tracer) eq 'CODE');
    $self->{'tracer'} = $tracer;
    return 1;
}

# Remove any trace routine set with [<cc>]set_tracer()[</cc>].
sub remove_tracer
{
    my $self = shift;

    $self->{'tracer'} = undef;
    return 1;
}

# Return the last insert id for a table and field
sub insert_id
{
    my $self = shift;
    my $table = shift;
    my $field = shift;

    #return $self->{'dbh'}->last_insert_id(??, ??, $table, $field);
    return $self->{'dbh'}->{'mysql_insertid'};
}

# Prepare and execute a query.
sub query
{
    my $self = shift;
    my $query = shift;

    if (ref($self->{'tracer'}) eq 'CODE'
        && ! $self->{'tracer'}->($self, $query)) {
        return undef;
    }

    my $q = $self->{'dbh'}->prepare($query);
    if (! $q->execute()) {
        #print STDERR "Error in query: '$query'\n";
        $self->set_last_error($q->errstr());
        croak "Error in query: '$query': " . $q->errstr();
        return undef;
    }
    return $q;
}

# Fetch a result line from a query returned by [<cc>]query()[</cc>].
sub fetch_array
{
    my $self = shift;
    my $q = shift;

    if (! $q) {
        confess("Nextis::Database::fetch_array() called with undefined query");
    }

    my $h = $q->fetchrow_hashref();
    return undef unless ($h);
    return { %{$h} };
}

1;
