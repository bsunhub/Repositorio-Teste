#
# Copyright (C) 2004 Next Internet Solutions.
#
# Nextis::RRDToolGraph - a Perl package to build RRDTool graph commands.
#

package Nextis::RRDToolGraph;

use strict;

use Carp;
use Data::Dumper;

use Nextis::ExprParser;

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

my @colors = ('#FF0000',
              '#00FF00',
              '#0000FF',
              '#FF00FF',
              '#00CFCF',
              '#BFBF00',
              '#7F7F7F');

# ------------------------------------------------------------------------

# operators recognized in expressions
my %expr_opers = (
                  '==' => 'EQ',
                  '!=' => 'NE',
                  '<'  => 'LT',
                  '<=' => 'LE',
                  '>'  => 'GT',
                  '>=' => 'GE',
                  '+' => '+',
                  '-' => '-',
                  '*' => '*',
                  '/' => '/',
                  '%' => '%',
                  );

# macros recognized in expressions
# [[WARNING: macros can NOT be self-referential, or _apply_macro() may
# be caught in an infinite recursion]]
my %expr_macros = (
                   '_CONT' => [ '*IF*', [ 'is_unk', '$1' ], '0', '$1' ],
                   );

# functions and macros recognized in expressions (with the number of
# expected arguments)
my %expr_funcs = (
                  'min' => [ 'MIN', 2 ],
                  'max' => [ 'MAX', 2 ],
                  'limit' => [ 'LIMIT', 3 ],

                  'is_unk' => [ 'UN', 1 ],
                  'is_inf' => [ 'ISINF', 1 ],

                  'sin' => [ 'SIN', 1 ],
                  'cos' => [ 'COS', 1 ],
                  'log' => [ 'LOG', 1 ],
                  'exp' => [ 'EXP', 1 ],
                  'sqrt' => [ 'SQRT', 1 ],
                  'atan' => [ 'ATAN', 1 ],
                  'atan2' => [ 'ATAN2', 2 ],
                  
                  'floor' => [ 'FLOOR', 1 ],
                  'ceil' => [ 'CEIL', 1 ],
                  'deg2rad' => [ 'DEG2RAD', 1 ],
                  'rad2deg' => [ 'RAD2DEG', 1 ],
                  
                  'trend' => [ 'TREND', 2 ],

                  '_CONT' => [ $expr_macros{'_CONT'}, 1 ],
                  );

# these are used to decide what is an user variable:
my @expr_post_vars = qw(UNKN INF NEGINF PREV COUNT NOW TIME LTIME);
my %expr_post_vars = map { $_ => 1 } @expr_post_vars;
my %expr_post_opers = map { $expr_opers{$_} => 1 } keys %expr_opers;
my %expr_post_funcs = map { $expr_funcs{$_}->[0] => 1 } keys %expr_funcs;
my %expr_post_extra = (
                       'IF' => 1,
                       );

# ------------------------------------------------------------------------

# Create a new [<cc>]RRDToolGraph[</cc>] object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'elements'} = [];
    $self->{'next_color_index'} = 0;
    $self->{'last_error'} = '';
    $self->{'colors'} = [ @colors ];

    bless($self, $class);

    return $self;
}

sub last_error
{
    my $self = shift;

    return $self->{'last_error'};
}

sub set_last_error
{
    my $self = shift;
    my $str = shift;

    return $self->{'last_error'} = $str;
}

# ----------------------------------------------------------------

sub _oper_to_postfix
{
    my $self = shift;
    my $oper = shift;

}

sub _is_user_variable
{
    my $self = shift;
    my $var = shift;

    if ($var =~ /^-?[\d.]+$/) {
        return 0;
    }

    if (! exists($expr_post_funcs{$var})
        && ! exists($expr_post_extra{$var})
        && ! exists($expr_post_vars{$var})
        && ! exists($expr_post_opers{$var})) {
        return 1;
    }
    return 0;
}

sub _apply_macro
{
    my $self = shift;
    my $macro_def = shift;
    my $args = shift;

    my $ret = [];
    for my $node (@{$macro_def}) {
        if (ref($node) eq 'ARRAY') {
            my $val = $self->_apply_macro($node, $args);
            return undef unless (defined($val));
            push @{$ret}, $val;
        } elsif ($node =~ /^\$(\d+)$/) {
            my $n = $1 - 1;
            return undef if ($n >= scalar(@{$ret}));
            push @{$ret}, $args->[$n];
        } else {
            push @{$ret}, $node;
        }
    }

    return $ret;
}

sub _expr_to_postfix
{
    my $self = shift;
    my $expr = shift;

    if (ref($expr) eq '') {
        return [ $expr ];
    }

    my @ret = ();
    for ($expr->[0]) {
        # function or macro call
        /^[A-Za-z0-9_]+$/ && do {
            my @args = @{$expr}[1..scalar(@{$expr})-1];
            my $func_info = $expr_funcs{$expr->[0]};
            if (! $func_info) {
                $self->set_last_error("ERROR: unknown function '$expr->[0]'");
                return undef;
            }
            if (scalar(@args) != $func_info->[1]) {
                $self->set_last_error("ERROR: expected $func_info->[1] argument(s) to '$expr->[0]', got " . scalar(@args));
                return undef;
            }

            # macro: expand and convert to postfix
            if (ref($func_info->[0]) eq 'ARRAY') {
                my $macro = $func_info->[0];
                my $result = $self->_apply_macro($macro, \@args);
                if (! defined($result)) {
                    $self->set_last_error("ERROR: macro expansion for '$expr->[0]' tried to use invalid parameter");
                    return undef;
                }
                return $self->_expr_to_postfix($result);
            }

            # native function call: convert arguments and append function name
            my $ret = [];
            for my $arg (@args) {
                my $x = $self->_expr_to_postfix($arg);
                return undef unless ($x);
                push @{$ret}, @{$x};
            }
            push @{$ret}, $func_info->[0];
            return $ret;
        };

        # IF
        /^\*IF\*$/ && do {
            my @args = ();
            for my $n (1, 2, 3) {
                my $x = $self->_expr_to_postfix($expr->[$n]);
                return undef unless $x;
                push @args, $x;
            }
            return [ @{$args[0]}, @{$args[1]}, @{$args[2]}, 'IF' ];
        };

        # list: return last value
        /^\*LIST\*$/ && do {
            if (scalar(@{$expr}) == 1) {
                return [];
            }
            return [ $expr->[scalar(@{$expr})-1] ];
        };

        # consider anything else an operator
        my $oper = $expr_opers{$expr->[0]};
        if (! defined($oper)) {
            $self->set_last_error("ERROR: unknown operator '$expr->[0]'");
            return undef;
        }
        my $ret = [];
        for my $arg (@{$expr}[1..scalar(@{$expr})-1]) {
            my $x = $self->_expr_to_postfix($arg);
            return undef unless ($x);
            push @{$ret}, @{$x};
        }
        push @{$ret}, $oper;
        return $ret;
    }
}

sub _parse_expr
{
    my $self = shift;
    my $str = shift;

    my $parser = new Nextis::ExprParser($str);
    my $expr = $parser->read_expr();
    if (! $expr) {
        $self->set_last_error($parser->last_error());
        return undef;
    }

    return $self->_expr_to_postfix($expr);
}

# ----------------------------------------------------------------

sub set_color
{
    my $self = shift;
    my $num = shift;
    my $color = shift;

    return $self->{'colors'}->[$num] = $color;
}

sub next_color
{
    my $self = shift;

    return $self->{'colors'}->[($self->{'next_color_index'}++)
                               % scalar(@{$self->{'colors'}})];
}

sub add_line1
{
    my $self = shift;
    my $expr = shift;
    my $label = shift;
    my $color = shift;
    my $extra = shift;

    return $self->add_element('LINE1', $expr, $label, $color, $extra);
}

sub add_line2
{
    my $self = shift;
    my $expr = shift;
    my $label = shift;
    my $color = shift;
    my $extra = shift;

    return $self->add_element('LINE2', $expr, $label, $color, $extra);
}

sub add_element
{
    my $self = shift;
    my $type = shift;
    my $expr_str = shift;
    my $label = shift;
    my $color = shift;
    my $extra = shift;

    if (! defined($color)) {
        $color = $self->next_color();
    }
    if (! defined($label)) {
        $label = '';
    }

    my $expr = $self->_parse_expr($expr_str);
    return undef unless ($expr);

    push @{$self->{'elements'}}, { 'type' => $type,
                                   'expr' => $expr,
                                   'label' => $label,
                                   'color' => $color,
                                   'extra' => $extra,
                                   'def_name' => undef, };
    return 1;
}

sub build_info
{
    my $self = shift;
    my $rrd_filename = shift;

    # read elements and get necessary DEFs and CDEFs
    my %defs = ();
    my %cdefs = ();
    my $next_id = 0;
    for my $el (@{$self->{'elements'}}) {
        my $expr = $el->{'expr'};
        if (scalar(@{$expr}) == 1
            && ref($expr->[0]) eq ''
            && $self->_is_user_variable($expr->[0])) {
            # simply use the variable, no need for a CDEF
            $defs{$expr->[0]}++;
            $el->{'def_name'} = $expr->[0];
            next;
        }

        for my $item (@{$expr}) {
            if ($self->_is_user_variable($item)) {
                $defs{$item}++;
            }
        }
        my $id = $next_id++;
        $cdefs{"id$id"} = join(',', @{$expr});
        $el->{'def_name'} = "id$id";
    }

    # build DEFs and CDEFs
    my @defs = ();
    for my $def_name (sort keys %defs) {
        push @defs, "DEF:$def_name=$rrd_filename:$def_name:AVERAGE";
    }
    my @cdefs = ();
    for my $cdef_id (sort keys %cdefs) {
        my $cdef = $cdefs{$cdef_id};
        push @cdefs, "CDEF:$cdef_id=\"$cdef\"";
    }

    # build graphic elements
    my @graphs = ();
    for my $el (@{$self->{'elements'}}) {
        my $gr = "$el->{'type'}:$el->{'def_name'}$el->{'color'}";
        if ($el->{'label'}) {
            $gr .= ":\"$el->{'label'}\"";
        }
        if ($el->{'extra'}) {
            $gr .= ":$el->{'extra'}";
        }

        push @graphs, $gr;
    }

    return {
        'defs' => [ sort @defs ],
        'cdefs' => [ sort @cdefs ],
        'graphs' => [ @graphs ],
    };
}

1;
