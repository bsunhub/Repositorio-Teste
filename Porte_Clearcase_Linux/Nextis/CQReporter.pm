
 package Nextis::CQReporter;

 use strict;
 use Carp;

 use Data::Dumper;

 use Nextis::Sexp;
 use Nextis::CQReport;

 our $AUTOLOAD;

 BEGIN {
     use Exporter();
     our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

     $VERSION     = 1.00;

     @ISA         = qw(Exporter);
     @EXPORT      = qw();
     %EXPORT_TAGS = ();
     @EXPORT_OK   = qw();
 }

 # Create a new [<cc>]Nextis::CQReporter[</cc>].  If [<cc>]$str[</cc>]
 # is given, read the reporter from the string (in symbolic expression
 # format).  Return the reporter object on success, or
 # [<cc>]undef[</cc>] on error.
 sub new
 {
     my $proto = shift;
     my $class = ref($proto) || $proto;
     my $self = {};

     my $str = shift;

     $self->{'str'} = undef;
     $self->{'root'} = [];
     bless($self, $class);

     if (defined($str)) {
         $self->{'str'} = $str;
         return undef unless $self->read($str);
     }

     return $self;
 }

 sub _unescape
 {
     my $self = shift;
     my $str = shift;

     return '' unless defined($str);

     $str =~ s/\\\{([0-9A-Fa-f]+)\}/chr(hex($1))/ge;
     return $str;
 }

 sub _read_query_node
 {
     my $self = shift;
     my $node = shift;

     # filter
     if ($node->[1]->[0] eq 'filter') {
         return [ $self->_unescape($node->[1]->[2]),
                  $self->_unescape($node->[1]->[1]),
                  $self->_unescape($node->[1]->[3]),
                  { 'pos' => [ $node->[2]->[1], $node->[2]->[2] ] } ];
     }

     # operator
     my $ret = [ $node->[1]->[0] ];
     for my $s (@{$node}[3..scalar(@{$node})-1]) {
         push @{$ret}, $self->_read_query_node($s);
     }
     push @{$ret}, { 'pos' => [ $node->[2]->[1], $node->[2]->[2] ] };
     return $ret;
 }

 sub _read_query
 {
     my $self = shift;
     my $query = shift;

     my $node = {};
     for my $part (@{$query}) {
         next if (ref($part) ne 'ARRAY');
         for ($part->[0]) {
             /^ent$/ && do {
                 $node->{'ent'} = $self->_unescape($part->[1]->[0]);
                 $node->{'ent_pos'} = [ $part->[2]->[1], $part->[2]->[2] ];
                 last;
             };

             /^fields$/ && do {
                 $node->{'fields'} = [];
                 for my $f (@{$part->[1]}) {
                     push @{$node->{'fields'}}, $self->_unescape($f);
                 }
                 $node->{'fields_pos'} = [ $part->[2]->[1], $part->[2]->[2] ];
                 last;
             };

             /^node$/ && do {
                 $node->{'filters'} = $self->_read_query_node($part);
                 last;
             };

             print STDERR "WARNING: query: unknown part '$part->[0]'\n";
         }
     }
     return $node;
 }

 sub _read_report_node
 {
     my $self = shift;
     my $proc = shift;

     my $node = {
         'name' => '',
         'data' => '',
         'output' => '',
     };

     for my $part (@{$proc}) {
         next if (ref($part) ne 'ARRAY');
         for ($part->[0]) {
             /^pos$/ && do {
                 $node->{'pos'} = [ $part->[1], $part->[2] ];
                 last;
             };

             /^query$/ && do {
                 $node->{'query'} = $self->_read_query($part);
                 last;
             };

             /^name$/ && do {
                 $node->{'name'} = $self->_unescape($part->[1]);
                 last;
             };

             /^data$/ && do {
                 $node->{'data'} = $self->_unescape($part->[1]);
                 last;
             };

             /^output$/ && do {
                 $node->{'output'} = $self->_unescape($part->[1]);
                 last;
             };

             print STDERR "WARNING: proc: unknown part '$part->[0]'\n";
         }
     }
     return $node;
 }

 sub _read_level
 {
         my $self = shift;
    my $level = shift;

    my $node = {
        'levels' => [],
    };
    for my $part (@{$level}) {
        next if (ref($part) ne 'ARRAY');
        for ($part->[0]) {
            /^level$/ && do {
                push @{$node->{'levels'}}, $self->_read_level($part);
                last;
            };

            /^proc$/ && do {
                $node->{'proc'} = $self->_read_report_node($part);
                last;
            };

            /^start$/ && do {
                $node->{'start'} = $self->_read_report_node($part);
                last;
            };

            /^end$/ && do {
                $node->{'end'} = $self->_read_report_node($part);
                last;
            };

            /^pos$/ && do {
                $node->{'pos'} = [ $part->[1], $part->[2] ];
                last;
            };

            print STDERR "WARNING: level: unknown part '$part->[0]'\n";
        }
    }

    return $node;
}

sub _read_report
{
    my $self = shift;
    my $sexp = shift;

    my $node = {
        'levels' => [],
    };
    for my $part (@{$sexp}) {
        next if (ref($part) ne 'ARRAY');
        for ($part->[0]) {
            /^level$/ && do {
                push @{$node->{'levels'}}, $self->_read_level($part);
                last;
            };

            /^pos$/ && do {
                $node->{'pos'} = [ $part->[1], $part->[2] ];
                last;
            };

            print STDERR "WARNING: report: unknown part '$part->[0]'\n";
        }
    }

    return $node;
}

# Read a reporter form a reporter string in symbolic expression format.
# Return true on success, [<cc>]undef[</cc>] on error.
sub read
{
    my $self = shift;
    my $str = shift;

    my $sexps = read_sexps($str);
    return undef unless ($sexps
                         && ref($sexps) eq 'ARRAY'
                         && ref($sexps->[scalar(@{$sexps})-1]) eq 'ARRAY');

    $self->{'root'} = $self->_read_report($sexps->[scalar(@{$sexps})-1]);
    return ($self->{'root'}) ? 1 : undef;
}

# Read a reporter from a reporter file.  Return true on success,
# [<cc>]undef[</cc>] on error.
sub read_from_file
{
    my $self = shift;
    my $filename = shift;

    if (! open(IN, "<$filename")) {
        return undef;
    }
    my $str;
    {
        local $/ = undef;
        $str = <IN>;
    }
    close(IN);

    return $self->read($str);
}

# ----------------------------------------------------------------------
# --- generate report stuff --------------------------------------------

sub _parse_value
{
    my $self = shift;
    my $value = shift;
    my $vars = shift;

    #my $orig_value = $value;

    return '' if (! defined($value));

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return '' if ($value eq '');

    if ($value !~ /^\"(.*)\"$/) {
        print STDERR "UNSUPPORTED FIELD REFERENCE IN VALUE\n";
        return $value;
    }
    $value =~ s/^\"(.*)\"$/$1/;

    my @ret = ();
    my ($p1, $p2);

    # unqualified variable reference
    if ($value =~ /^\$\{([^\.]+)\}$/) {
        $p1 = $vars->{'*default*'};
        $p2 = $1;
    }
    # qualified variable reference
    if ($value =~ /^\$\{([^\.]+)\.([^\.]+)\}$/) {
        $p1 = $1;
        $p2 = $2;
    }

    # variable
    if (defined($p1) && defined($p2)) {
        if (! exists($vars->{"\L$p1"})
            || ! exists($vars->{"\L$p1"}->{"\L$p2"})) {
            return '';
        }
        return $vars->{"\L$p1"}->{"\L$p2"};
    }
    return $value;
}

sub _parse_level_vars
{
    my $self = shift;
    my $vars = shift;
    my $data = shift;

    my @lines = split(/\n+/, $data);
    for my $line (@lines) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        $line =~ s/\r//g;
        next if ($line eq '');
        my ($var, $val) = split(/\s*=\s*/, $line);
        $vars->{$vars->{'*default*'}}->{"\L$var"} = $self->_parse_value($val, $vars);
    }
}

sub _get_query_filters
{
    my $self = shift;
    my $node = shift;

    for ($node->[0]) {
        # AND operator
        /^and$/i && do {
            my $ret = [ 'and' ];
            for (my $i = 1; $i < scalar(@{$node}); $i++) {
                next unless (ref($node->[$i]) eq 'ARRAY');
                push @{$ret}, $self->_get_query_filters($node->[$i]);
            }
            return $ret;
        };

        # OR operator
        /^or$/i && do {
            my $ret = [ 'or' ];
            for (my $i = 1; $i < scalar(@{$node}); $i++) {
                next unless (ref($node->[$i]) eq 'ARRAY');
                push @{$ret}, $self->_get_query_filters($node->[$i]);
            }
            return $ret;
        };

        # some filter
        return [ $node->[0], $node->[1], $node->[2] ];
    }

    return [];
}

sub _check_cond
{
    my $self = shift;
    my $cond = shift;
    my $vars = shift;

    my @parts = split(/\s*(==|!=|<>|<|<=|>|>=)\s*/, $cond);
    if (scalar(@parts) != 3) {
        print STDERR "ERROR: Syntax error on IF condition '$cond'\n";
        return undef;
    }

    my $val1 = $self->_parse_value($parts[0], $vars);
    my $val2 = $self->_parse_value($parts[2], $vars);
    
    for ($parts[1]) {
        /^==$/ && do { return (($val1 cmp $val2) == 0) ? 1 : 0; };
        /^!=$/ && do { return (($val1 cmp $val2) != 0) ? 1 : 0; };
        /^<>$/ && do { return (($val1 cmp $val2) != 0) ? 1 : 0; };
        /^<$/  && do { return (($val1 cmp $val2) <  0) ? 1 : 0; };
        /^<=$/ && do { return (($val1 cmp $val2) <= 0) ? 1 : 0; };
        /^>$/  && do { return (($val1 cmp $val2) >  0) ? 1 : 0; };
        /^>=$/ && do { return (($val1 cmp $val2) >= 0) ? 1 : 0; };
    }
    print STDERR "ERROR: Unknown operator '$parts[1]' on IF condition\n";
    return 0;
}

sub _parse_statements
{
    my $self = shift;
    my $out = shift;
    my $spec = shift;
    my $vars = shift;
    my $strings = shift;
    my $blocks = shift;

    #print STDERR "STATEMENTS($spec)\n";

    while (42) {
        $spec =~ s/^[\r\s]+//g;
        if ($spec =~ s[^if\s*\(([^\)]*)\)\s*<BLOCK:(\d+)>\s*else\s*<BLOCK:(\d+)>\s*]{}) {
            # IF (...) {} ELSE {}
            my $cond = $1;
            my $con = $2;
            my $alt = $3;
            
            $cond =~ s/<STRING:(\d+)>/"\"$strings->[$1]\""/ge;
            if ($self->_check_cond($cond, $vars)) {
                $self->_parse_statements($out, $blocks->[$con], $vars,
                                         $strings, $blocks);
            } else {
                $self->_parse_statements($out, $blocks->[$alt], $vars,
                                         $strings, $blocks);
            }
        } elsif ($spec =~ s[^if\s*\(([^\)]*)\)\s*<BLOCK:(\d+)>]{}) {
            # IF (...) {}
            my $cond = $strings->[$1];
            my $con = $2;
            
            $cond =~ s/<STRING:(\d+)>/"\"$strings->[$1]\""/ge;
            if ($self->_check_cond($cond, $vars)) {
                $self->_parse_statements($blocks->[$con], $vars,
                                         $strings, $blocks);
            }
        } elsif ($spec =~ s/^<STRING:(\d+)>\s*=\s*<STRING:(\d+)>\s*;//) {
            # "name" = "val"
            my $name = $strings->[$1];
            my $val = $strings->[$2];
            push @{$out->{'*order*'}}, $name;
            $out->{"\L$name"} = $self->_parse_value("\"$val\"", $vars);
        } elsif ($spec =~ s/^<STRING:(\d+)>\s*=\s*([^;]+)\s*;//) {
            # "name" = field
            my $name = $strings->[$1];
            my $f = $2;
            #print STDERR "CAMPO($name, $f)\n";
            push @{$out->{'*order*'}}, $name;
            $out->{"\L$name"} = $vars->{$vars->{'*default*'}}->{"\L$f"};
        } elsif ($spec =~ /[^\s]/) {
            print STDERR "Syntax error on SPEC: '$spec'\n";
            last;
        } else {
            last;
        }
    }
}

sub _parse_output_spec
{
    my $self = shift;
    my $spec = shift;
    my $fields = shift;
    my $vars = shift;

    my @strings = ();
    my @blocks = ();

    # extract strings
    $spec =~ s[\"([^\"]*)\"]{
        my $n = scalar(@strings);
        push @strings, $1;
        "<STRING:$n>";
    }ge;

    # extract blocks
    while ($spec =~ s[\{([^\}]*)\}]{
        my $n = scalar(@blocks);
        push @blocks, $1;
        "<BLOCK:$n>";
    }ge) {}

    $spec =~ s/\r?\n/ /g;

    #print STDERR "PARSING OUTPUT SPEC: $spec\n";

    # parse statements
    my $out = {
        '*order*' => [],
    };
    $self->_parse_statements($out, $spec, $vars, \@strings, \@blocks);

    return $fields if (scalar(@{$out->{'*order*'}}) == 0);
    return $out;
}

sub _build_level_query
{
    my $self = shift;
    my $db = shift;
    my $level = shift;
    my $vars = shift;

    # build query
    my $query = $level->{'proc'}->{'query'};
    my $filters = $self->_get_query_filters($query->{'filters'});
    return $db->query($query->{'ent'}, $query->{'fields'},
                      $filters, $vars);
}

sub _generate_level
{
    my $self = shift;
    my $qb = shift;
    my $level = shift;
    my $vars = shift;

    my $level_name = $level->{'proc'}->{'name'};

    # parse start and end to get vars
    $vars->{'*default*'} = "\L$level_name";
    for my $part (qw(start end)) {
        $self->_parse_level_vars($vars, $level->{$part}->{'data'});
    }

    my $q = $self->_build_level_query($qb, $level, $vars);

    #print STDERR Dumper($level->{'proc'}->{'query'});

    my $data = {
        'name' => $level_name,
        'start' => {},
        'rows' => [],
        'end' => [],
    };

    $data->{'start'} = $self->_parse_output_spec($level->{'start'}->{'output'},
                                                 { '*order*' => [] }, $vars);

    my $line;
    while ($line = $qb->fetch_array($q)) {
        my $fields = {
            '*order*' => [],
        };

        # collect results
        for my $k (keys %{$line}) {
            next if ($k =~ /^\d+$/);
            push @{$fields->{'*order*'}}, $k;
            $fields->{"\L$k"} = $line->{$k};
        }

        # set variables so they can be used in sub-levels
        for my $k (keys %{$fields}) {
            $vars->{$level_name}->{$k} = $fields->{$k};
        }

        # process sub-levels
        for my $sub_level (@{$level->{'levels'}}) {
            my $s = $self->_generate_level($qb, $sub_level, $vars);
            push @{$fields->{'*order*'}}, $s->{'name'};
            $fields->{$s->{'name'}} = {
                'start' => $s->{'start'},
                'rows' => $s->{'rows'},
                'end' => $s->{'end'},
            };
        }

        $fields = $self->_parse_output_spec($level->{'proc'}->{'output'},
                                            $fields,
                                            $vars);
        push @{$data->{'rows'}}, $fields;
    }

    $data->{'end'} = $self->_parse_output_spec($level->{'end'}->{'output'},
                                               { '*order*' => [] }, $vars);
    return $data;
}

# Generate the report using a [<cc>]Nextis::CQQueryBuilder[</cc>]
# object.  Return the resulting [<cc>]Nextis::CQReport[</cc>] object,
# or [<cc>]undef[</cc>] on error.
sub generate
{
    my $self = shift;
    my $qb = shift;
    my %parms = @_;

    my $vars = { 'parm' => \%parms };
    my $data = { };
    for my $level (@{$self->{'root'}->{'levels'}}) {
        my $s = $self->_generate_level($qb, $level, $vars);
        $data->{$s->{'name'}} = {
            'start' => $s->{'start'},
            'rows' => $s->{'rows'},
            'end' => $s->{'end'},
        };
    }
    
    return new Nextis::CQReport($data);
}

# ------------------------------------------------------------------------
# --- XML output stuff ---------------------------------------------------

# Return the reporter in a string in symbolic expression format.
sub get_sexp_string
{
    my $self = shift;

    return $self->{'str'};
}

sub _xml_escape
{
    my $self = shift;
    my $str = shift;

    return '' unless defined($str);

    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/\"/&quot;/g;
    $str =~ s/\'/&apos;/g;
    return $str;
}

sub _xml_get_pos
{
    my $self = shift;
    my $pos = shift;
    
    return "x=\"" . $self->_xml_escape($pos->[0]) . "\""
        . " y=\"" . $self->_xml_escape($pos->[1]) . "\"";
}

sub _xml_get_query_node
{
    my $self = shift;
    my $node = shift;

    #$xml .= "<![CDATA[" . Dumper($query) . "]]>";
    
    if ($node->[0] eq 'and' || $node->[0] eq 'or') {
        #return "<![CDATA[" . Dumper($node) . "]]>";

        my $s = '';
        my $pos = undef;
        for (my $i = 1; $i < scalar(@{$node}); $i++) {
            if (ref($node->[$i]) ne 'ARRAY') {
                $pos = $node->[$i]->{'pos'};
                last;
            }
            $s .= $self->_xml_get_query_node($node->[$i]);
        }
        return "<node type=\"op\" op=\"$node->[0]\" "
            . $self->_xml_get_pos($pos) . ">"
            . $s . "</node>";
    }
    
    return "<node type=\"filter\" "
        . "val1=\"" . $self->_xml_escape($node->[1]) . "\" "
        . "cmp=\"" . $self->_xml_escape($node->[0]) . "\" "
        . "val2=\"" . $self->_xml_escape($node->[2]) . "\" "
        . $self->_xml_get_pos($node->[3]->{'pos'})
        . " />";
}

sub _xml_get_query
{
    my $self = shift;
    my $query = shift;

    my $xml = "<query>";

    #$xml .= "<![CDATA[" . Dumper($query) . "]]>";

    # entity
    $xml .= "<entity name=\"" . $self->_xml_escape($query->{'ent'}) ."\" "
        . $self->_xml_get_pos($query->{'ent_pos'}) . "/>";

    # fields
    $xml .= "<fields " . $self->_xml_get_pos($query->{'fields_pos'}) . ">";
    for my $f (@{$query->{'fields'}}) {
        $xml .= "<field name=\"" . $self->_xml_escape($f) . "\" />";
    }
    $xml .= "</fields>";

    # filters
    $xml .= "<filters>";
    $xml .= $self->_xml_get_query_node($query->{'filters'});
    $xml .= "</filters>";

    $xml .= "</query>";
    return $xml;
}

sub _xml_get_level
{
    my $self = shift;
    my $level = shift;

    #print Dumper($level);

    my $xml = "<level>";

    # proc, start, end
    for my $part (qw(start proc end)) {
        next unless exists($level->{$part});
        $xml .= "<$part " . $self->_xml_get_pos($level->{$part}->{'pos'}) . ">";
        for my $name (qw(name data output)) {
            next unless exists($level->{$part}->{$name});
            $xml .= "<$name>";
            $xml .= $self->_xml_escape($level->{$part}->{$name});
            $xml .= "</$name>";
        }
        if (exists($level->{$part}->{'query'})) {
            $xml .= $self->_xml_get_query($level->{$part}->{'query'});
        }
        $xml .= "</$part>";
    }

    # levels
    for my $level (@{$level->{'levels'}}) {
        $xml .= $self->_xml_get_level($level);
    }
    $xml .= "</level>";
}

# Return the reporter in a string in XML format.
sub get_xml_string
{
    my $self = shift;

#    my $xml = <<"ENDH";
#<?xml version="1.0" ?>
#<!DOCTYPE reporter [
#  <!ATTLIST info id ID #REQUIRED>
#  <!ATTLIST level id ID #REQUIRED>
#]>
#ENDH
#;

    #print Dumper($self->{'root'});

    my $xml = '<?xml version="1.0" ?>' . "\n";
    $xml .= "<reporter>";
    $xml .= "<root " . $self->_xml_get_pos($self->{'root'}->{'pos'}) . ">";
    for my $level (@{$self->{'root'}->{'levels'}}) {
        $xml .= $self->_xml_get_level($level);
    }
    $xml .= "</root>";
    $xml .= "</reporter>";
    return $xml;

}

1;
