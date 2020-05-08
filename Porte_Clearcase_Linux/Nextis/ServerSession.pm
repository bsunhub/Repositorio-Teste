#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Template - a Perl package manage a ClearQuest session.
#

package Nextis::ServerSession;

# This package manages the objects in a ClearQuest session in the
# server side.  It also has provisions to keep other data (variables,
# filenames, network transfered bytes) along with the session.

use strict;
use Carp;
use Digest::MD5;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# Create a new [<cc>]ServerSession[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $id = shift;

    my $cur_time = time();

    $self->{'id'} = $id;
    $self->{'cq_session_obj_id'} = undef;
    $self->{'cq_admin_session_obj_id'} = undef;
    $self->{'has_login'} = undef;
    $self->{'creation_ts'} = $cur_time;
    $self->{'last_tx'} = $cur_time;
    $self->{'tx_info'} = {};
    $self->{'objs'} = {};
    $self->{'vars'} = {};
    $self->{'filenames'} = {};
    $self->{'datanames'} = {};

    bless($self, $class);
    return $self;
}

my $gen_id = sub {
    return Digest::MD5::md5_base64(rand(1000000));
};

# Return the session id.
sub get_id
{
    my $self = shift;
    return $self->{'id'};
}

# Set the last transmission timestamp in the session.
sub set_last_tx
{
    my $self = shift;
    my $ts = shift || time();

    return $self->{'last_tx'} = $ts;
}

# Return 1 if the session is logged in, 0 or undef if not.
sub has_login
{
    my $self = shift;

    return $self->{'has_login'};
}

# Set the value returned by has_login().
sub set_has_login
{
    my $self = shift;
    my $has_login = shift;

    $self->{'has_login'} = $has_login;
}

# Return the timestamp of the creation of the session.
sub creation_ts
{
    my $self = shift;
    
    return $self->{'creation_ts'};
}

# Return the last transmission timestamp in the session, as set by
# [<cc>]set_last_tx()[</cc>].
sub last_tx
{
    my $self = shift;
    
    return $self->{'last_tx'};
}

# Return a reference to a hash containing the network transmission
# information for the session.
sub tx_info
{
    my $self = shift;

    return $self->{'tx_info'};
}

# Return the number of objects interned in the session.
sub num_objects
{
    my $self = shift;

    return scalar(keys(%{$self->{'objs'}}));
}

# Get the id of the CQSession object from the session.
sub get_cq_session_obj_id
{
    my $self = shift;

    return $self->{'cq_session_obj_id'};
}

# Get the id of the CQAdminSession object from the session.
sub get_cq_admin_session_obj_id
{
    my $self = shift;
    return $self->{'cq_admin_session_obj_id'};
}

# Get the reference to the CQSession object from the session.
sub get_cq_session
{
    my $self = shift;

    return $self->get_object($self->{'cq_session_obj_id'});
}

# Get the reference to the CQAdminSession object from the session.
sub get_cq_admin_session
{
    my $self = shift;

    return $self->get_object($self->{'cq_admin_session_obj_id'});
}

# Intern a data in the session. Return the new data id in the session.
sub intern_data
{
    my $self = shift;
    my $data = shift;
    
    my $new_id;
    do {
        $new_id = $gen_id->();
    } while (exists($self->{'datanames'}->{$new_id}));
    $self->{'datanames'}->{$new_id} = $data;
    return $new_id;
}

# Return the data associated with a data ID
sub get_data
{
    my $self = shift;
    my $id = shift;

    return $self->{'datanames'}->{$id};
}

# Remove the data diven its ID
sub remove_data
{
    my $self = shift;
    my $id = shift;

    delete $self->{'datanames'}->{$id};
    return 1;
}

# Intern a file in the session.  Return the new file id in the session.
sub intern_filename
{
    my $self = shift;
    my $filename = shift;

    my $new_id;
    do {
        $new_id = $gen_id->();
    } while (exists($self->{'filenames'}->{$new_id}));
    $self->{'filenames'}->{$new_id} = $filename;
    return $new_id;
}


# Remove a file from the session, given its id.  The file is deleted
# from the filesystem and its id is removed from the session.
sub remove_file
{
    my $self = shift;
    my $id = shift;

    my $filename = $self->get_filename($id);
    return undef unless $filename;

    unlink($filename);
    $filename =~ s|[^/\\]+$||;
    rmdir($filename);
    return 1;
}

# Remove all files from the session.  Files are deleted from the
# filesystem and their ids are removed from the session.
sub remove_all_files
{
    my $self = shift;

    my $dir = undef;
    for my $id (keys %{$self->{'filenames'}}) {
        my $filename = $self->get_filename($id);
        unlink($filename);
        $dir = $filename;
        $dir =~ s|[^/\\]+$||;
    }
    $self->{'filenames'} = {};
    rmdir($dir) if ($dir);
    return 1;
}

# Get the name of a session file given its id.
sub get_filename
{
    my $self = shift;
    my $id = shift;

    return $self->{'filenames'}->{$id};
}

# Return a reference to a hash with the session variables.
sub get_variables
{
    my $self = shift;

    return $self->{'vars'};
}

# Set the value of a session variable.
sub set_variable
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    $self->{'vars'}->{$name} = $value;
    return 1;
}

# Get the value of a session variable.
sub get_variable
{
    my $self = shift;
    my $name = shift;

    return $self->{'vars'}->{$name};
}

# Get an object given its reference.  Return a reference to an array
# containing the object id and the object reference, or
# [<cc>]undef[</cc>] if the object doesn't exist in the session.
sub get_object_by_ref
{
    my $self = shift;
    my $obj = shift;

    if (! defined($obj)) {
        warn "get_object_by_ref called with garbage object";
    }

    for my $k (keys %{$self->{'objs'}}) {
        if ($self->{'objs'}->{$k}->[1] == $obj) {
            return $self->{'objs'}->{$k};
        }
    }
    return undef;
}

# Get an object given the object id.  Return a reference to the
# object, or [<cc>]undef[</cc>] if there is no object with the given
# id.
sub get_object
{
    my $self = shift;
    my $obj_id = shift;

    my $o = $self->{'objs'}->{$obj_id};
    if (! defined($o)) {
        return undef;
    }
    return $o->[1];
}

# Intern the given object in the session.  Return the new object id.
sub intern_object
{
    my $self = shift;
    my $obj = shift;
    
    my $new_id;
    do {
        $new_id = $gen_id->();
    } while (exists($self->{'objs'}->{$new_id}));
    $self->{'objs'}->{$new_id} = [ $new_id, $obj, 1 ];
    return $new_id;
}

# Intern the ClearQuest Session object.  Return the new object id.
sub create_cq_session
{
    my $self = shift;
    my $cq_session = shift;
    
    return $self->{'cq_session_obj_id'} = $self->intern_object($cq_session);
}

# Intern the ClearQuest AdminSession object.  Return the new object id.
sub create_cq_admin_session
{
    my $self = shift;
    my $cq_admin_session = shift;
    
    return $self->{'cq_admin_session_obj_id'} = $self->intern_object($cq_admin_session);
}

# Increase the reference counter to an object.  Return the new
# reference count, or [<cc>]undef[</cc>] if the object is not in the
# session.
sub ref_object
{
    my $self = shift;
    my $obj = shift;

    return 1 if (ref($obj) =~ /CQSession$/);
    return 1 if (ref($obj) =~ /CQAdminSession$/);

    my $id = $self->get_object_by_ref($obj);
    return undef unless $id;
    $id = $id->[0];

    return ++$self->{'objs'}->{$id}->[2];
}

# Decrease the reference counter to an object and remove it from the
# session if it drops below 1.  Return the new reference count (may be
# zero), or [<cc>]undef[</cc>] if the object is not in the session.
sub unref_object
{
    my $self = shift;
    my $obj = shift;

    return 1 if (ref($obj) =~ /CQSession$/);
    return 1 if (ref($obj) =~ /CQAdminSession$/);

    my $id = $self->get_object_by_ref($obj);
    return undef unless $id;
    $id = $id->[0];

    my $refs = --$self->{'objs'}->{$id}->[2];
    if ($refs <= 0) {
        delete($self->{'objs'}->{$id});
        return 0;
    }
    return $refs;
}

1;
