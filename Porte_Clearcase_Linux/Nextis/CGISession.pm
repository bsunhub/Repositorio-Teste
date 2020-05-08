#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::CGISession - a Perl package to manage a CGI session.
#

package Nextis::CGISession;

# This package has functions to assist in the handling of CGI sessions.

use strict;
use Nextis::Template;
use Nextis::Config;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&get_cgi_session &get_light_cgi_session
                      &get_tpl_for_session &end_cgi_session
                      &redir &run_session_file &is_exit_death);
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}

# Redirect the browser to another URL
sub redir
{
    my $url = shift;

    print "<html><head><meta http-equiv=\"refresh\" content=\"0; url=$url\"></head></html>\n";
}

# Return 1 if the exception in [<cc>]$e[</cc>] (copied from
# [<cc>]$@[</cc>], caused by a [<cc>]die()[</cc>] in an [<cc>]eval{
# ... }[</cc>]) is due to an [<cc>]exit()[</cc>], or 0 otherwise.  This
# can only happen while running under ModPerl, where
# [<cc>]exit()[</cc>] dies instead of terminating the process.
sub is_exit_death
{
    my $e = shift;

    if ($e
        && ref($e) eq 'APR::Error'
        #&& $e == ModPerl::EXIT
        ) {
        return 1;
    }
    return 0;
}

# Run code from a file defined in the cgi.cfg template configuration
sub run_session_file
{
    my $conn = shift;
    my $file = shift;
    my @parms = shift;

    my $cfg = new Nextis::Config($conn->get_variable('cgi_config_file'));
    if ($cfg) {
        my $base_lang = $cfg->get_value('template', 'base_lang_dir');
        my $filename = $cfg->get_value('template', $file);
        if ($base_lang && $filename) {
            if (open(INIT, "<$base_lang/$filename")) {
                my $old_sep = $/;
                $/ = undef;
                my $file = <INIT>;
                $/ = $old_sep;
                close(INIT);
                my $code = eval($file);
                if ($@) {
                    print STDERR "$@\n";
                } else {
                    $code->($conn, @parms) if (ref($code) eq 'CODE');
                }
            }
        }
    }

    return 0;
}

# Retrieve the CQProxy connection using the browser session (cookie)
# and return a new Nextis::Template, or redirect the browser to the
# login page and return undef.
sub get_cgi_session
{
    my $cgi = shift;
    my $conn = shift;
    my $must_have_login = shift;

    my $sess_id = $cgi->cookie('cq_sess_id');

    $must_have_login = 0 unless defined($must_have_login);

    # retrieve session
    if (defined($sess_id) && $sess_id ne '') {
        if (! $conn->set_session($sess_id)) {
            $sess_id = '';
        }
    }
    if (! defined($sess_id) || $sess_id eq '') {
        print $cgi->header();
        redir('login.pl?exp=1') if $must_have_login;
        return undef;
    }
    my $has_login = $conn->get_variable('login');
    $has_login = '0' unless defined $has_login;
    if ($must_have_login && $has_login ne '1') {
        print $cgi->header();
        redir('login.pl?exp=1');
        return undef;
    }

    # set IP and last request time
    $conn->set_variable('last_access_host', $cgi->remote_host());

    my $tpl = get_tpl_for_session($conn, $must_have_login);
    $tpl->add_var('login', $has_login);

    # print the header setting the cookie
    my $cookie = $cgi->cookie(-name => 'cq_sess_id',
                              -value => $sess_id);
    print $cgi->header(-cookie => $cookie);
    return $tpl;
}

sub get_tpl_for_session
{
    my $conn = shift;

    # create template and fill it with session variables
    my $tpl = new Nextis::Template($conn->get_variable('cgi_config_file'));
    $tpl->add_var('login_username', $conn->get_variable('login_username'));
    $tpl->add_var('last_query', $conn->get_variable('last_query'));
    $tpl->add_var('last_query_type', $conn->get_variable('last_query_type'));
    $tpl->add_var('last_entity', $conn->get_variable('last_entity'));
    $tpl->add_var('lang', $conn->get_variable('login_language'));
    for (qw(login_username last_query last_query_type last_entity)) {
        $tpl->add_var("u_$_", urlencode($tpl->var($_)));
    }
    my %lang_info = ('language'   => $conn->get_variable('login_language'),
                     'schema_rep' => $conn->get_variable('login_schema_rep'),
                     'database'   => $conn->get_variable('login_database'),
                     'schema_rev' => $conn->get_variable('login_schema_rev'));
    $tpl->set_lang_info(\%lang_info);

    run_session_file($conn, 'retrieve_session', $tpl);

    return $tpl;
}

# Retrieve the CQProxy connection using the browser session (cookie).
sub get_light_cgi_session
{
    my $cgi = shift;
    my $conn = shift;

    my $sess_id = $cgi->cookie('cq_sess_id');

    # retrieve session
    if (defined($sess_id) && $sess_id ne '') {
        if (! $conn->set_session($sess_id)) {
            $sess_id = '';
        }
    }
    if (! defined($sess_id) || $sess_id eq '') {
        return undef;
    }

    return 1;
}

# Terminate a session (destroy it and unset its cookie)
sub end_cgi_session
{
    my $cgi = shift;
    my $conn = shift;
    my $sess_id = $cgi->cookie('cq_sess_id');

    if (defined($sess_id) && $sess_id ne '') {
        if (! $conn->set_session($sess_id)) {
            $sess_id = '';
        }
    }
    if (! defined($sess_id) || $sess_id eq '') {
        print $cgi->header();
        redir('login.pl?exp=1');
        return undef;
    }

    $conn->end_session();

    my $cookie = $cgi->cookie(-name => 'cq_sess_id',
                              -value => '');
    print $cgi->header(-cookie => $cookie);
    return 1;
}

1;
