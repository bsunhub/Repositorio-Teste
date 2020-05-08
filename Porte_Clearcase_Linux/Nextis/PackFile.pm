#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::PackFile - a Perl package to handle zip-family files.
#

package Nextis::PackFile;

# This package handles ZIP, JAR, EAR, WAR and related files.

use strict;
use Carp;

use Cwd;
use Data::Dumper;

use Nextis::CommandRunner;

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

# Create a new [<cc>]Nextis::PackFile[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $filename = shift;
    my $options = shift;

    $self->{'filename'} = $filename;
    $self->{'user_data'} = {};
    $self->{'options'} = undef;
    $self->{'base_tmp_path'} = undef;
    $self->{'content_path'} = undef;
    $self->{'content'} = [];
    bless($self, $class);

    if ($options && ! $self->set_options($options)) {
        return undef;
    }

    return $self;
}

# Get the last error message.
sub last_error
{
    my $self = shift;

    return $self->{'last_error'};
}

# Set the message returned by [<cc>]last_error()[</cc>].
sub set_last_error
{
    my $self = shift;
    my $str = shift;

    return $self->{'last_error'} = $str;
}

sub content
{
    my $self = shift;

    return $self->{'content'};
}

sub user_data
{
    my $self = shift;

    return $self->{'user_data'};
}

sub content_path
{
    my $self = shift;

    return $self->{'content_path'};
}

sub base_tmp_path
{
    my $self = shift;

    return $self->{'base_tmp_path'};
}

sub filename
{
    my $self = shift;

    return $self->{'filename'};
}

sub _gen_tmp_dir
{
    my $self = shift;
    my $prefix = shift;

    my $str = lc(int(rand(1000000)) . $$);
    if (defined($prefix)) {
        $str = lc($prefix) . $str;
    }
    $str =~ s/[^a-z0-9_]/_/g;
    return $str;
}

sub set_options
{
    my $self = shift;
    my $options = shift;

    if (! defined($options->{'tmp_dir'})) {
        return 0;
    }

    do {
        $self->{'base_tmp_path'} = "$options->{'tmp_dir'}/" . $self->_gen_tmp_dir($options->{'dir_prefix'});
    } while (-d $self->{'base_tmp_path'});
    $self->{'content_path'} = "$self->{'base_tmp_path'}/unpack";
    if (defined($options->{'zip_command'})) {
        $self->{'zip_cmd'} = new Nextis::CommandRunner($options->{'zip_command'});
    }
    if (defined($options->{'unzip_command'})) {
        $self->{'unzip_cmd'} = new Nextis::CommandRunner($options->{'unzip_command'});
    }
    if (defined($options->{'list_command'})) {
        $self->{'list_cmd'} = new Nextis::CommandRunner($options->{'list_command'});
    }
    return 1;
}

sub _list_dir
{
    my $self = shift;
    my $dir = shift;

    my @files = ();
    return [] unless opendir(DIR, $dir);
    while (my $file = readdir(DIR)) {
        next if ($file eq '.' || $file eq '..');
        push @files, $file;
    }
    closedir(DIR);

    return [ @files ];
}

sub _read_content
{
    my $self = shift;
    my $base_path = shift;
    my $base_name = shift;
    my $content = shift;
    my $read_dirs = shift;

    if ($base_name ne '') { $base_name .= '/'; }

    my $files = $self->_list_dir($base_path);
    for my $file (@{$files}) {
        my $is_dir = -d "$base_path/$file";
        if (! $is_dir || $read_dirs) {
            push @{$content}, "$base_name$file";
        }
        if ($is_dir) {
            $self->_read_content("$base_path/$file", "$base_name$file",
                                 $content, $read_dirs);
        }
    }

    return 1;
}

sub list
{
    my $self = shift;
    
    my $cmd = $self->{'list_cmd'};
    if (! $cmd) {
        $self->set_last_error("ERROR: command for 'list' not defined");
        return undef;
    }
    my $args = {
        'zip_file' => $self->{'filename'},
    };
    my $ok = $cmd->run($args, 1);
    if (! $ok || $cmd->exit_code() != 0) {
        $self->set_last_error("ERROR RUNNING COMMAND '"
                              . $cmd->cmdline() . "' (exit code: " . $cmd->exit_code() . "):\n"
                              . "-----------------------------------------\n"
                              . $cmd->output()
                              . "-----------------------------------------\n");
        return undef;
    }
    return $cmd->output();
}

sub unzip
{
    my $self = shift;
    my $extra_data = shift;
    
    mkdir($self->{'base_tmp_path'}, 0755);
    mkdir($self->{'content_path'}, 0755);
    my $args = {
        'zip_file' => $self->{'filename'},
        'path' => $self->{'content_path'},
    };
    if ($extra_data) {
        for my $k (keys %{$extra_data}) {
            $args->{$k} = $extra_data->{$k};
        }
    }
    my $cmd = $self->{'unzip_cmd'};
    if (! $cmd) {
        $self->set_last_error("ERROR: command for 'unzip' not defined");
        return undef;
    }
    my $ok = $cmd->run($args, 1);
    if (! $ok || $cmd->exit_code() != 0) {
        $self->set_last_error("ERROR RUNNING COMMAND '"
                              . $cmd->cmdline() . "' (exit code: " . $cmd->exit_code() . "):\n"
                              . "-----------------------------------------\n"
                              . $cmd->output()
                              . "-----------------------------------------\n");
        return 0;
    }
    $self->{'content'} = [];
    $self->_read_content($self->{'content_path'}, '', $self->{'content'}, 0);
    return 1;
}

sub zip
{
    my $self = shift;
    my $dest_file = shift;

    my $cmd = $self->{'zip_cmd'};
    if (! $cmd) {
        $self->set_last_error("ERROR: command for 'zip' not defined");
        return undef;
    }
    my $args = {
        'zip_file' => $dest_file,
        'path' => '.',
    };
    my $cwd = getcwd();
    chdir($self->{'content_path'});
    my $ok = $cmd->run($args, 1);
    chdir($cwd);
    if (! $ok || $cmd->exit_code() != 0) {
        $self->set_last_error("ERROR RUNNING COMMAND '"
                              . $cmd->cmdline() . "':\n"
                              . "-----------------------------------------\n"
                              . $cmd->output()
                              . "-----------------------------------------\n");
        return 0;
    }
    
    return 1;
}

sub _cleanup_tree
{
    my $self = shift;
    my $dir = shift;

    my $list = [];
    $self->_read_content($dir, '', $list, 1);
    for my $rel (sort { length($b) <=> length($a) } @{$list}) {
        my $path = "$dir/$rel";
        if (-d $path) {
            rmdir($path);
        } else {
            unlink($path);
        }
    }
    rmdir($dir);
}

sub cleanup_content
{
    my $self = shift;

    my $dir = $self->{'content_path'};
    if (! $dir || length($dir) < 8) {
        print STDERR "WARNING: refusing to cleanup tree '$dir'\n";
        return undef;
    }
    $self->_cleanup_tree($dir);
    return 0;
}

sub cleanup
{
    my $self = shift;

    $self->cleanup_content();
    my $dir = $self->{'base_tmp_path'};
    if (! $dir || length($dir) < 8) {
        print STDERR "WARNING: refusing to cleanup tree '$dir'\n";
        return undef;
    }
    $self->_cleanup_tree($dir);
    return 0;
}

1;
