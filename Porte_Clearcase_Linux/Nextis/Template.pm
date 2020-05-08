#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::Template - a Perl package to parse templates.
#

package Nextis::Template;

# This package is used to interprete templates, supporting
# translations and user defined functions to be called from the
# template.
#
# Usage example:
#
#[<code>]
# use Nextis::Template;
#
# $tpl = new Nextis::Template();
# $tpl->add_var('test', 'value of template variable "test"');
# $tpl->add_var('message' => 'Some message',
#               'error' => 'Error message');
#
# sub simple_func
# {
#   my $tpl = shift;
#   my $parms = shift;
#
#   return 'This is the return value';
# }
#
# sub loop_func
# {
#   my $tpl = shift;
#   my $parms = shift;
#   my @ret = ();
#
#   push @ret, { 'name' => 'name of first line',
#                'description' => 'some description' };
#   push @ret, { 'name' => 'name of second line',
#                'description' => 'some other description' };
#   return \@ret;
# }
#
# $tpl->add_func('simple_func' => \&simple_func,
#                'loop_func' => \&loop_func);
#
# $tpl->generate('test.tpl');
#[</code>]

use strict;
use Nextis::Translate;
use Nextis::Config;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&xmlentities &htmlentities &urlencode &urldecode);
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}

# Escape HTML entities from the string.
sub htmlentities
{
    my $str = shift;

    $str = '' unless defined($str);

    $str =~ s/&/&amp;/g;
    $str =~ s/\"/&quot;/g;
    $str =~ s/\'/&apos;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    return $str;
}

# Escape XML entities from the string.
sub xmlentities
{
    my $str = shift;

    $str = '' unless defined($str);

    $str =~ s/&/&amp;/g;
    $str =~ s/\"/&quot;/g;
    $str =~ s/\'/&apos;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    return $str;
}

# Encode URL (change invalid URL characters to '[<cc>]%XX[</cc>]')
sub urlencode
{
    my $str = shift || '';

    $str =~ s{([ \?/&+=%\'\":\x80-\xff])}{"%" . sprintf("%02X", ord($1))}eg;
    return $str;
}

# Decode an URL encoded by [<cc>]urlencode[</cc>].
sub urldecode
{
    my $str = shift || '';

    $str =~ s{%([A-Fa-f0-9][A-Fa-f0-9])}{chr(hex($1))}eg;
    return $str;
}

# ---------------------------------------------------------

my ($tpl_if_compare, $tpl_for, $tpl_campo, $tpl_foreach);

$tpl_if_compare = sub {
    my ($v1, $op, $v2) = @_;

    for ($op) {
        /^in$/ && do {
            my @vals = split(/\s*,\s*/, $v2);
            return (grep { $v1 eq $_ } @vals) ? 1 : 0;
        };
        /^==$/ && do { return $v1 eq $v2; };
        /^!=$/ && do { return $v1 ne $v2; };
        /^<$/  && do { return $v1 <  $v2; };
        /^<=$/ && do { return $v1 <= $v2; };
        /^>$/  && do { return $v1 >  $v2; };
        /^>=$/ && do { return $v1 >= $v2; };
    }
    return 0;
};

$tpl_campo = sub {
    my $tpl = shift;
    my $vals = shift;

    return $tpl->var($vals->[0]);
};

$tpl_for = sub {
    my $tpl = shift;
    my $vals = shift;
    my @ret = ();

    my $var = $vals->[0];
    my $start = $vals->[1];
    my $end = $vals->[2];
    my $step = $vals->[3];
    $step = 1 unless defined($step);

    for (my $i = $start; $i < $end; $i += $step) {
        push @ret, { $var => $i };
    }

    return \@ret;
};

$tpl_foreach = sub {
    my $tpl = shift;
    my $vals = shift;
    my @ret = ();

    my $var = $vals->[0];
    my $fim = scalar(@{$vals}) - 1;
    my $num = 0;
    for my $item (@{$vals}[1 .. $fim]) {
        push @ret, { $var => $item, 'num' => $num++ };
    }

    return \@ret;
};

# ---------------------------------------------------------

# Helper function to build return value for loop functions with only
# one variable (named [<cc>]$name[</cc>]) per line.
sub to_lines
{
    my $self = shift;
    my $name = shift;
    my @vals = @_;

    my @ret = ();
    foreach (@vals) {
        push(@ret, { $name => $_ });
    }
    return \@ret;
}

# ---------------------------------------------------------

# Build a new Template generator.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $cgi_config_file = shift;
    $cgi_config_file = '' unless defined($cgi_config_file);

    bless($self, $class);
    $self->{'cgi_config_file'} = $cgi_config_file;
    $self->reset();

    return $self;
}

sub DESTROY
{
    my $self = shift;

    $self->{'file_stack'} = [];
    $self->{'output'} = '';
    $self->{'var_stack'} = [];
    $self->{'func_stack'} = [];
    $self->{'vars'} = {};
    #$self->{'funcs'} = {};   # this causes a segmentation fault in Perl
    return 1;
}

# Reset the status of the Template generator.
sub reset
{
    my $self = shift;

    my $cfg = undef;
    if (defined($self->{'cgi_config_file'}) && $self->{'cgi_config_file'} ne '') {
        $cfg = new Nextis::Config($self->{'cgi_config_file'});
    }

    if ($cfg) {
        $self->{'base_lang_dir'} = $cfg->get_value('template','base_lang_dir');
        $self->{'default_lang'} = $cfg->get_value('template','default_lang');
    } else {
        $self->{'base_lang_dir'} = '.';
        $self->{'default_lang'} = undef;
    }
    $self->{'default_lang'} = 'pt_BR' unless $self->{'default_lang'};

    $self->{'trans'} = new Nextis::Translate();
    $self->{'lang_info'} = {};
    $self->{'lang_dirs'} = [ $self->{'base_lang_dir'} ];
    
    $self->{'opt'} = {
        'show_error' => 1,
        'out_str' => 0
    };

    $self->{'file_stack'} = [];
    $self->{'output'} = '';
    $self->{'var_stack'} = [];
    $self->{'func_stack'} = [];
    $self->{'info'} = {};
    $self->{'vars'} = {};
    $self->{'funcs'} = {
        'for' => $tpl_for,
        'foreach' => $tpl_foreach,
        'campo' => $tpl_campo
    };

    if ($cfg) {
        $self->add_var('debug_js', $cfg->get_value('template','debug_js')||'');
        if ($cfg->get_value('template', 'color_translation')) {
            $self->{'trans'}->colorize(1);
        }
        my $init_pl_file = $cfg->get_value('template', 'init_tpl');
        if ($init_pl_file) {
            my $err = $self->read_init_pl($self->{'base_lang_dir'}
                                          . "/$init_pl_file");
            $self->log_err($err) if ($err);
        }
    }

    return 1;
}

# Set the Template language info.  This function reads the language
# files corresponding to the language requested.  If the 'language' is
# not given in the [<cc>]$info[</cc>] parameter, the default defined
# in the configuration file (if one was given) will be used.
# [<code>]
# $info = {
#           'language' => '...',
#           'schema_rep' => '...',
#           'database' => '...',
#           'schema_rev' => '...'
#         };
# [</code>]
sub set_lang_info
{
    my $self = shift;
    my $info = shift;

    $self->{'lang_info'} = $info;

    if (! defined($self->{'lang_info'}->{'language'})) {
        $self->{'lang_info'}->{'language'} = $self->{'default_lang'};
    }

    # read language info
    my $language = $self->{'lang_info'}->{'language'};
    my $schema_rep = $self->{'lang_info'}->{'schema_rep'};
    my $database = $self->{'lang_info'}->{'database'};
    my $schema_rev = $self->{'lang_info'}->{'schema_rev'};

    # select directories to read files from
    my @dirs = ($self->{'base_lang_dir'});
    if ($language) {
        push(@dirs, "$self->{'base_lang_dir'}/$language");
        if ($schema_rep && $database) {
            my $base = "$self->{'base_lang_dir'}/$language/schema/$schema_rep/$database";
            if ($schema_rev && -d "$base/$schema_rev") {
                push @dirs, "$base/$schema_rev";
            } elsif (-d "$base/default") {
                push @dirs, "$base/default";
            } else {
                my $cfg = new Nextis::Config("$base/default.cfg");
                if ($cfg) {
                    my $dir = $cfg->get_value('schema', 'default_version');
                    push @dirs, "$base/$dir" if ($dir && -d "$base/$dir");
                }
            }
        }
    }
    my @rev_dirs = reverse(@dirs);
    $self->{'lang_dirs'} = \@rev_dirs;

    # read the translate info from the directories
    for my $dir (@dirs) {
        $self->{'trans'}->load_message_file("$dir/errors.txt");
        $self->{'trans'}->load_field_file("$dir/strings.txt");
    }

    return undef;
}

# Return the current language info.
sub get_lang_info
{
    my $self = shift;

    return $self->{'lang_info'};
}

# Define the current language directories.
sub set_lang_dirs
{
    my $self = shift;
    my @list = shift;

    $self->{'lang_dirs'} = [ @list ];
}

# Return the current defined language directories, i.e., the list of
# directories in which the 'tpl/' directory will be searched for
# templates.
sub get_lang_dirs
{
    my $self = shift;

    return $self->{'lang_dirs'};
}

# Get the filename for a requested template.  This function scans all
# the current language directories for the existence of the file, and
# returns the first found filename, or [<cc>]undef[</cc>] if the file
# is not found.
sub get_tpl_filename
{
    my $self = shift;
    my $in_file = shift;

    for my $dir (@{$self->get_lang_dirs()}) {
        if (-e "$dir/tpl/$in_file") {
            return "$dir/tpl/$in_file";
        }
    }
    return undef;
}

# Return the translator for this template.
sub get_translate
{
    my $self = shift;

    return $self->{'trans'};
}

# Return the default translation context for the current file processing.
sub get_translation_context
{
    my $self = shift;
    my $suffix = shift || '';

    # get the root parent being processed
    my $file = $self->{'file_stack'}->[0]->[0] || '';

    return $file . $suffix;
}

# Return [<cc>]1[</cc>] if the given string has a field translation in
# the given context with the current language, [<cc>]0[</cc>] if not.
sub has_translation
{
    my $self = shift;
    my $ctx = shift;
    my $str = shift;

    if (! defined($str)) {
        $str = $ctx;
        $ctx = $self->get_translation_context();
    }
    return $self->{'trans'}->field_has_translation($ctx, $str);
}

# Translate a string given the context.
sub translate
{
    my $self = shift;
    my $ctx = shift;
    my $str = shift;

    if (! defined($str)) {
        $str = $ctx;
        $ctx = $self->get_translation_context();
    }

    return $self->{'trans'}->translate_field($ctx, $str);
}

# Read the init.pl file as defined in the configuration.
sub read_init_pl
{
    my $self = shift;
    my $init_pl_file = shift;

    # read the file
    if (! open(INIT, "<$init_pl_file")) {
        return "can't open '$init_pl_file'";
    }
    my $old_sep = $/;
    $/ = undef;
    my $file = <INIT>;
    $/ = $old_sep;
    close(INIT);

    # run the code
    my $code = eval($file);
    if ($@) { return $@; }
    $code->($self) if (ref($code) eq 'CODE');
    return undef;
}

# Save a list of variables and set them to a new specified value:
# [<code>]
# %vars = (
#           'var1' => new_value,
#           '...' => ...
#         );
# [</code>]
sub push_var
{
    my $self = shift;
    my %vars = @_;

    my $save = {};
    for my $k (keys %vars) {
        $save->{$k} = $self->{'vars'}->{$k};
        $self->{'vars'}->{$k} = $vars{$k};
    }
    push @{$self->{'var_stack'}}, $save;
    return 1;
}

# Restore a list if variables saved with [<cc>]push_var[</cc>].
sub pop_var
{
    my $self = shift;

    return undef unless scalar(@{$self->{'var_stack'}}) > 0;

    my $s = pop @{$self->{'var_stack'}};
    for my $k (keys %{$s}) {
        $self->{'vars'}->{$k} = $s->{$k};
    }
    return 1;
}

# Add one or more information to the Template information list.  The
# information can be accessed  with the method [<cc>]info[</cc>].
sub add_info
{
    my $self = shift;
    my %infos = @_;

    foreach (keys %infos) {
        $self->{'info'}->{$_} = $infos{$_};
    }
    return 1;
}

# Add one or more functions to the Template function list.  The
# function can be called from the template page with the given name or
# with the method [<cc>]func[</cc>].
# [<code>]
# %funcs = (
#            'name1' => \&my_function_1,
#            'name2' => sub { ... }
#          );
# [</code>]
sub add_func
{
    my $self = shift;
    my %funcs = @_;

    foreach (keys %funcs) {
        $self->{'funcs'}->{$_} = $funcs{$_};
    }
    return 1;
}

# Add one or more variables to the Template variable list.  The
# variables can be accessed from the template page or with the method
# [<cc>]var[</cc>].
sub add_var
{
    my $self = shift;
    my %vars = @_;

    foreach (keys %vars) {
        $self->{'vars'}->{$_} = $vars{$_};
    }
    return 1;
}

# Return the value of the information with the specified name in the
# template information list, or [<cc>]undef[</cc>] if there is no
# variable with that name.
sub info
{
    my $self = shift;
    my $name = shift;

    return $self->{'info'}->{$name};
}

# Return the function with the specified name in the template function
# list, or [<cc>]undef[</cc>] if there is no function with that name.
sub func
{
    my $self = shift;
    my $func = shift;

    if (exists($self->{'funcs'}->{$func})
        && defined($self->{'funcs'}->{$func})
        && ref($self->{'funcs'}->{$func}) eq 'CODE') {
        return $self->{'funcs'}->{$func};
    }
    return undef;
}

# Return the value of the variable with the specified name in the
# template variable list, or [<cc>]''[</cc>] (the empty string) if
# there is no variable with that name.
sub var
{
    my $self = shift;
    my $var = shift;

    if (exists($self->{'vars'}->{$var}) && defined($self->{'vars'}->{$var})) {
        return $self->{'vars'}->{$var};
    }
    return '';
}

# Show the error template with the given message and title.
sub show_error
{
    my $self = shift;
    my $msg = shift;
    my $title = shift;

    if (! $title) {
        my $t = $self->translate('error.tpl', 'CTC10000_titulo');
        $title = "CTC - 10000: $t" unless $title;
    }

    if ($msg =~ /^(\s*<font[^>]*>)(.*)(<\/font>\s*)$/) {
        $msg = $1 . htmlentities($2) . $3;
    } else {
        $msg = htmlentities($msg);
    }

    $self->add_var('error', $title);
    $self->add_var('msg', $msg);
    my $ret = $self->generate("error.tpl", { 'show_error' => 0 });
    if (! defined($ret)) {
        $self->output("Content-type: text/html\r\n\r\n");
        $self->output("Error reading template to show error message:<br>\n");
        $self->output("<b>$msg</b>.\n");
        return undef;
    }
    return 1;
}

# Log a message in the webserver log (hopefully).
sub log_err
{
    my $self = shift;
    my $str = shift;

    my $file = $self->get_file();
    if ($file) {
        $str = "ERROR: $file: $str";
    } else {
        $str = "ERROR: $str";
    }

    print STDERR "$str\n";
}

# Return the parsed value of the given string in [<cc>]$val[</cc>].
# This function interprets variables: strings in the form
# "[<cc>]$var[</cc>]" yeld the value of the variable "$var" .
sub parse_value
{
    my $self = shift;
    my $val = shift;

    if ($val =~ /^\$/) {
        return $self->var($self->parse_value(substr($val, 1)));
    }
    return $val;
}

# Parse a string in the form [<cc>]"str1" op "str2"[</cc>] into an
# array [<cc>]('val1', 'op', 'val2')[</cc>] where [<cc>]val1[</cc>]
# and [<cc>]val2[</cc>] are the values of [<cc>]"str1"[</cc>] and
# [<cc>]"str2"[</cc>], respectively (subject to interpretation:
# "[<cc>]$var[</cc>]" becomes the value of the variable 'var', etc).
# Return a reference to the resulting array.
sub get_if_parms
{
    my $self = shift;
    my $txt = shift;

    if ($txt !~ s/^\s*\"([^\"]*)\"//) { return undef; }
    my $val1 = $self->parse_value($1);

    if ($txt !~ s/^\s*([=!<>in]+)//) { return undef; }
    my $op = $1;

    if ($txt !~ s/^\s*\"([^\"]*)\"//) { return undef; }
    my $val2 = $self->parse_value($1);

    return [ $val1, $op, $val2 ];
}

# Parse a string in the form [<cc>]"val1","val2",...,"valn"[</cc>]
# into an array [<cc>]('v1', 'v2', ..., 'vn')[</cc>] where each of the
# '[<cc>]vi[</cc>]' are the values in the original string (subject to
# interpretation: "[<cc>]$var[</cc>]" becomes the value of the
# variable 'var', etc).  Return a reference to the resulting array.
sub get_func_parms
{
    my $self = shift;
    my $vals = shift;

    # Split the values and remove quotes
    my @vals = split(/\"\s*,\s*\"/, $vals);
    if (scalar(@vals) == 1 && $vals[0] =~ /^\"(.*)\"$/) {
        $vals[0] = $1;
    } elsif (scalar(@vals) >= 2) {
        $vals[0] = substr($vals[0], 1);
        $vals[scalar(@vals)-1] = substr($vals[scalar(@vals)-1], 0,
                                        length($vals[scalar(@vals)-1])-1);
    }

    # Parse the values
    my @ret = ();
    foreach my $val (@vals) {
        push @ret, $self->parse_value($val);
    }
    return \@ret;
}

# Internal function to generate templates.  Use [<cc>]generate[</cc>]
# instead.
sub gen
{
    my $self = shift;
    my $i_ini = shift;
    my $i_end = shift;
    my $lines = shift;

    for (my $i = $i_ini; $i < $i_end; $i++) {
        my $l = $lines->[$i];

        # <!-- INCLUDE -->
        if ($l =~ /^\s*<!--\s*INCLUDE\(\"([^\"]*)\"\)\s*-->\s*$/i) {
            my $file = $self->parse_value($1);
            my $ret = $self->generate($file);
            if ($self->{'opt'}->{'out_str'}) {
                $self->output($ret);
            }
            next;
        }

        # <!-- SET -->
        if ($l =~ /^\s*<!--\s*SET\s*\(\s*\"([^,]+)\"\s*,\s*\"([^,]+)\"\s*\)\s*-->\s*$/i) {
            my $var = $1;
            my $val = $self->parse_value($2);
            $self->add_var($var, $val);
            next;
        }

        # <!-- PUSH -->
        if ($l =~ /^\s*<!--\s*PUSH\(([^\)]*)\)\s*-->\s*$/i) {
            my $vals = $self->get_func_parms($1);
            my $var = shift(@{$vals});
            $self->{'vars'}->{$var} = []
                if (! defined($self->{'vars'}->{$var})
                    || ref($self->{'vars'}->{$var}) ne 'ARRAY');
            for my $val (@{$vals}) {
                push @{$self->{'vars'}->{$var}}, $val;
            }
            next;
        }
        
        # <!-- IF -->
        if ($l =~ /^\s*<!--\s*IF\s*\(([^\)]*)\)\s*-->\s*$/i) {
            my $parms = $self->get_if_parms($1);

            if (! defined($parms)) {
                $self->log_err("$i: syntax error in IF parameters.");
                return;
            }

            # search the loop end
            my @if_pos = [ $parms, $i ];
            my $if_prof = 0;
            for (; $i < $i_end; $i++) {
                #$self->output("search endif: <tt>" . htmlentities($lines->[$i]) . "</tt>");
                if ($lines->[$i] =~ /^\s*<!--\s*IF\s*\(/i) {
                    $if_prof++;
                } elsif ($lines->[$i] =~ /^\s*<!--\s*ELSIF\s*\(([^\)]*)\)\s*-->/i) {
                    if ($if_prof == 1) {
                        my $parms = $self->get_if_parms($1);
                        if (! defined($parms)) {
                            $self->log_err("$i: syntax error in ELSIF parameters.");
                            return;
                        }
                        push @if_pos, [ $parms, $i ];
                    }
                } elsif ($lines->[$i] =~ /^\s*<!--\s*ELSE\s*-->/i) {
                    if ($if_prof == 1) {
                        push @if_pos, [ 1, $i ];
                    }
                } elsif ($lines->[$i] =~ /^\s*<!--\s*ENDIF\s*-->/i) {
                    $if_prof--;
                    if ($if_prof == 0) {
                        push @if_pos, [ undef, $i ];
                        last;
                    }
                }
            }
            if ($if_prof != 0) {
                my $func_start = $if_pos[0]->[1];
                $self->log_err("$func_start: unterminated IF");
                return;
            }

            # transform from if positions to segments (intervals)
            my @if_seg = ();
            my $last_cmp = undef;
            my $last_pos = -1;
            for my $pos (@if_pos) {
                if ($last_pos >= 0) {
                    push @if_seg, [ $last_cmp, $last_pos+1, $pos->[1] ];
                }
                $last_cmp = $pos->[0];
                $last_pos = $pos->[1];
            }

            # test the segments in order and parse the one that is true
            for my $seg (@if_seg) {
                my $vals = $seg->[0];
                if ($vals == 1
                    || $tpl_if_compare->($vals->[0], $vals->[1], $vals->[2])) {
                    $self->gen($seg->[1], $seg->[2], $lines);
                    last;
                }
            }
            next;
        }
        
        # <!-- GENERIC_FUNCTIONS(...) -->
        if ($l =~ /^\s*<!--\s*([a-zA-Z0-9_]+)\(([^\)]*)\)\s*-->\s*$/) {
            my $func = $1;
            my $parms = $self->get_func_parms($2);

            # search the loop end
            my $func_start = $i + 1;
            my $func_end = -1;
            my $func_prof = 0;
            for (; $i < $i_end; $i++) {
                if ($lines->[$i] =~ /^\s*<!--\s*${func}\(/) {
                    $func_prof++;
                } elsif ($lines->[$i] =~ /^\s*<!--\s*${func}\s+END\s*-->\s*/) {
                    $func_prof--;
                    if ($func_prof == 0) {
                        $func_end = $i;
                        last;
                    }
                }
            }
            if ($func_end < 0) {
                $self->log_err("$func_start: unterminated function: $func");
                return;
            }

            # Call the function and iterate through the results
            my $rets = undef;
            my $call_func = $self->func($func);
            if (defined($call_func)) {
                $rets = $call_func->($self, $parms);
                if (ref($rets) ne 'ARRAY') { next; }
                foreach my $ret (@{$rets}) {
                    if (ref($ret) eq 'CODE') {
                        $ret->($self, $parms);
                    } elsif (ref($ret) eq 'HASH') {
                        my %save = ();
                        foreach my $k (keys %{$ret}) {
                            $save{$k} = $self->{'vars'}->{$k};
                            $self->{'vars'}->{$k} = $ret->{$k};
                        }
                        $self->gen($func_start, $func_end, $lines);
                        foreach my $k (keys %{$ret}) {
                            $self->{'vars'}->{$k} = $save{$k};
                        }
                    } else {
                        $self->log_err("$func_start: bad line returned by loop function");
                    }
                }
            } else {
                $self->log_err("$func_start: UNKNOWN FUNCTION: $func");
            }
            next;
        }

        # <?tpl func("parms") ?>
        $l =~ s[<\?tpl\s*([a-zA-Z0-9_]+)\(([^\)]*?)\)\s*\?>]{
            my $func = $1;
            my $parms = $self->get_func_parms($2);
            my $tpl_func = $self->func($func);

            if (defined($tpl_func)) {
                my $x = $tpl_func->($self, $parms);
                if (! defined($x)) {
                    '';
                } else {
                    $x;
                }
            } else {
                $self->log_err("$i: UNKNOWN FUNCTION: $func");
                '';
            }
        }eg;

        # <?= $var ?>
        $l =~ s[<\?=\s*(\$+[a-zA-Z0-9\._]+)\s*\?>]{
            $self->parse_value($1);
        }eg;

        $self->output("$l\n");
    }
};

# Return the output of a template if [<cc>]generate[</cc>] was called
# to generate the output to a string.
sub get_output
{
    my $self = shift;

    my $ret = $self->{'output'};
    $self->{'output'} = '';
    return $ret;
}

# Send output to the template output.  This is used internally by
# [<cc>]generate()[</cc>].
sub output
{
    my $self = shift;
    my $str = shift;

    if ($self->{'opt'}->{'out_str'}) {
        $self->{'output'} .= $str;
    } elsif (defined($self->{'opt'}->{'out_fh'})) {
        my $fh = $self->{'opt'}->{'out_fh'};
        print $fh $str;
    } elsif (defined($self->{'opt'}->{'out_func'})) {
        $self->{'opt'}->{'out_func'}->($str);
    } else {
        print $str;
    }
    return 1;
}

# Return [<cc>]1[</cc>] if the given template input file exists in one
# of the search directories, [<cc>]0[</cc>] if not.
sub template_exists
{
    my $self = shift;
    my $file = shift;

    return ($self->get_tpl_filename($file)) ? 1 : 0;
}

# Return the file being processed.
sub get_file
{
    my $self = shift;

    return '' unless (ref($self->{'file_stack'}) eq 'ARRAY');
    return '' if (scalar(@{$self->{'file_stack'}}) < 1);
    return $self->{'file_stack'}->[scalar(@{$self->{'file_stack'}})-1]->[0];
}

# Save the current processed file (and possibly its absolute pathname)
# in the file stack and replace it with a new file that will be
# processed.
sub push_file
{
    my $self = shift;
    my $file = shift;
    my $pathname = shift;

    push @{$self->{'file_stack'}}, [ $file, $pathname ];
    return 1;
}

# Restore the file being processed.
sub pop_file
{
    my $self = shift;

    pop @{$self->{'file_stack'}};
    return 1;
}

# Generate a template given its file name and options:
# [<code>]
# $opt = {
#   'show_error' => 0,          # 1 to show errors
#   'out_str' => 0,             # 1 to output to string, read with get_output()
#   'out_fh' => $out_fh,        # output filehandle
#   'out_func' => sub { ... },  # output function
# };
# [</code>]
sub generate
{
    my $self = shift;
    my $in_file = shift;
    my $opt = shift;

    $opt = {} unless (defined $opt && ref($opt) eq 'HASH');

    # read the input file
    my $filename = $self->get_tpl_filename($in_file);
    if (! $filename) {
        $self->log_err("Template file '$in_file' not found");
        return undef;
    }
    my $fh = undef;
    if (! open($fh, "<$filename")) {
        $self->log_err("Error opening template file '$filename' (requested: '$in_file')");
        return undef;
    }
    my @file = <$fh>;
    close($fh);
    chomp(@file);

    # save old state and set new
    my $old_out = $self->{'output'};
    my %old_opt = %{$self->{'opt'}};
    $self->{'output'} = '';
    for (keys %{$opt}) {
        $self->{'opt'}->{$_} = $opt->{$_};
    }
    $self->push_file($in_file, $filename);

    # generate
    my ($ret, $died);
    my $ok = eval {
        $ret = $self->gen(0, scalar(@file), \@file);
        1;
    };
    if (! $ok) {
        $died = $@;
    }
    if ($ret && $opt->{'show_error'}) {
        $self->output("Error reading template '$in_file'\n");
    }
    my $new_out = $self->get_output();

    # restore old state
    $self->pop_file();
    $self->{'opt'} = \%old_opt;
    $self->{'output'} = $old_out;

    if ($died) {
        die $died;
    }

    return $new_out;
}

1;
