#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::ExprParser - a Perl package to parse arithmetic expressions.
#

package Nextis::ExprParser;

# This package implements a simple expression parser.  It supports
# expressions containing:
# [<code>]
# numbers              integer and floating point
# variables            any name
# function calls       any name, any number of arguments
# binary operators     +, -, *, /, %, <, >, <=, >=, ==, !=, ||, &&
# unary operators      -, !
# conditionals         cond_expr ? consequent_expr : alternative_expr
# lists                (expr, expr, ...)
# [</code>]
#
# Input is done via any object that supports the method
# "[<cc>]get()[</cc>]" to read characters.  To read input from a
# string, use the package [<cc>]Nextis::InputString[</cc>] (used
# automatically if you pass a string as the input).  The package
# [<cc>]Nextis::InputFile[</cc>] may be used to input from a file.
#
# To read an expression, simply set the input and call
# [<cc>]read_expr()[</cc>].  The expression will be read until end of
# input.  If an error occurs in the middle of the expression,
# [<cc>]undef[</cc>] is returned and the last error is set to the
# cause of the error (use [<cc>]last_error()[</cc>] to read it).
# Otherwise, the expression tree is returned.
#
# [<title>]Notes, Caveats and Limitations[</title>]
#
# [<ul>]
#   [<li>] Lists are returned as [<cc>][ '*LIST*', ... ][</cc>],
#   except when the list is the argument of a function call.  So, for
#   example: "a+(b,c)" gives [<cc>][ '+', 'a', [ '*LIST*', 'b', 'c'
#   ]][</cc>], but "min(a,b)" gives [<cc>][ 'min', 'a', 'b' ][</cc>].[</li>]
#
#   [<li>] Negative numbers are always read as a number prefixed by
#   the unary minus.[</li>]
# 
#   [<li>] Unary minus (-) is stored as '-u', so the expression "-1"
#   results in [<cc>][ '-u', 1 ][</cc>].[</li>]
#
#   [<li>] Function calls do not require use of parenthesis: an
#   operand immediatelly following another constitute a function call
#   (the first is the function, the second is the argument).  Note
#   that function calls associate from right to left, so "a b c" means
#   "(a(b))(c)" and not "a(b(c))".  The "normal" usage (i.e., with
#   parenthesis) always gives the expected results.[</li>]
# [</ul>]
#
# [<title>]Example[</title>]
#
# [<code>]
# my $parser = new Nextis::ExprParser('2 * (1.5 + sin(x))');
# my $expr = $parser->read_expr();
# # $expr should be: [ '*', '2', [ '+', '1.5', [ 'sin', 'x' ] ] ];
# print Dumper($expr);
# [</code>]

use strict;

use Data::Dumper;

use Nextis::InputString;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

# This is for the tokenizer.  NOTICE: the tokenizer assumes that
# operators ALWAYS have 1 or 2 characters.
my @op_tokens = ('?', ':', ',',
                 '=', '||', '&&',
                 '<', '>', '<=', '>=', '==', '!=',
                 '+', '-',
                 '*', '/', '%',
                 '!',
                 '(', ')');
my %op_tokens = map { $_ => 1 } @op_tokens;

# This is for the expression parser.
my %op_assoc_right = (
                      '-u' => 1,
                      '!' => 1,
                      ',' => 1,
                      '?' => 1,
                      );
my %op_prec = (
               ',' => 10,
               '?' => 20,
               ':' => 30,

               '=' => 40,
               '||' => 50,
               '&&' => 50,

               '==' => 60,
               '!=' => 60,
               '<' => 60,
               '>' => 60,
               '<=' => 60,
               '>=' => 60,

               '+' => 70,
               '-' => 70,
               
               '/' => 80,
               '*' => 80,
               '%' => 80,

               '-u' => 90,
               '!' => 90,
               );

# Create a new expression parser.  If an argument is given, it is
# treated as the input (see comments for [<cc>]set_input()[</cc>]).
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'input'} = undef;
    $self->{'buf'} = '';
    $self->{'last_error'} = '';
    bless($self, $class);

    my $input = shift;
    if (defined($input)) {
        $self->set_input($input);
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

# Set the source from where expressions are read.  [<cc>]$input[</cc>]
# may be a string or any object that supports the
# [<cc>]get($num_chars)[</cc>] method (e.g.,
# [<cc>]Nextis::InputString[</cc>] or [<cc>]Nextis::InputFile[</cc>]).
sub set_input
{
    my $self = shift;
    my $input = shift;

    if (ref($input) eq '') {
        $input = new Nextis::InputString($input);
    }
    $self->{'input'} = $input;
    $self->{'buf'} = '';
    return undef;
}

# Get [<cc>]$len[</cc>] characters (default: [<cc>]1[</cc>]) from the
# current input.
sub get
{
    my $self = shift;
    my $len = shift || 1;

    my $ret = '';
    if (length($self->{'buf'}) > 0) {
        if (length($self->{'buf'}) >= $len) {
            $ret = substr($self->{'buf'}, 0, $len);
            $self->{'buf'} = substr($self->{'buf'}, $len);
            return $ret;
        }
        $ret = $self->{'buf'};
        $len -= length($self->{'buf'});
        $self->{'buf'} = '';
    }
    my $tmp = $self->{'input'}->get($len);
    if (! defined($tmp)) {
        return undef if ($ret eq '');
        return $ret;
    }
    return $ret . $tmp;
}

# Un-get a string.  Subsequent calls to [<cc>]get()[</cc>] will read
# from this string before reading from the current input.
sub unget
{
    my $self = shift;
    my $str = shift;

    if (! defined($str)) {
        $str = '';
    }

    $self->{'buf'} = $str . $self->{'buf'};
    return 0;
}

sub _char_same_class
{
    my $self = shift;
    my $ch1 = shift;
    my $ch2 = shift;

    if (length($ch1) != 1 || length($ch2) != 1) {
        return 0;
    }

    return 1 if ($ch1 =~ /[a-z0-9_.]/i && $ch2 =~ /[a-z0-9_.]/i);
    return 1 if ($ch1 !~ /[a-z0-9_.]/i && $ch2 !~ /[a-z0-9_.]/i);
    return 0;
}

# Read a token from the input, skipping white space.  Return
# [<cc>]undef[</cc>] on end of input, or the token that was read.
sub read_token
{
    my $self = shift;

    my $ch;
    do {
        $ch = $self->get();
    } while (defined($ch) && length($ch) > 0 && $ch =~ /\s/);
    if (! defined($ch) || length($ch) == 0) {
        return undef;
    }

    if ($ch eq '(' || $ch eq ')') {
        return $ch;
    }
    my $str = $ch;

    while (42) {
        my $new_ch = $self->get();

        # if we got end-of-input or whitespace, we're done
        if (! defined($new_ch) || length($new_ch) == 0 || $new_ch =~ /\s/) {
            return $str;
        }

        # if we have an operator now but not with the next char, we're done
        if ($op_tokens{$str} && ! $op_tokens{"$str$new_ch"}) {
            $self->unget($new_ch);
            return $str;
        }

        # if the next char is of a different class from the first, we're done
        if (! $self->_char_same_class($new_ch, $ch)) {
            $self->unget($new_ch);
            return $str;
        }

        $str .= $new_ch;
    }
}

# Combine the top of the operator stack with a suitable number of
# operands from the operand stack and push the result in the operand
# stack.  Return 1 if ok, [<cc>]undef[</cc>] on error (and set the
# last error).
sub _combine_stack
{
    my $self = shift;
    my $opr_stack = shift;
    my $opn_stack = shift;

    if (scalar(@{$opr_stack}) == 0) {
        $self->set_last_error("ERROR: empty operator stack");
        return undef;
    }

    #print "OPERATORS: ", Dumper($opr_stack);
    #print "OPERANDS:  ", Dumper($opn_stack);

    my $opr = pop @{$opr_stack};
    my $nargs = undef;
    for ($opr) {
        /^\?$/ && do {
            $self->set_last_error("ERROR: bad syntax for '?' operator");
            return undef;
        };

        # process x?y:z
        /^:$/ && do {
            if (scalar(@{$opr_stack}) == 0
                || $opr_stack->[scalar(@{$opr_stack})-1] ne '?') {
                $self->set_last_error("ERROR: bad if expression");
                return undef;
            }
            pop @{$opr_stack};  # remove '?' from stack
            $opr = '*IF*';
            $nargs = 3;
            last;
        };

        # process list
        /^,$/ && do {
            if (grep { $_ ne ',' } @{$opr_stack}) {
                $self->set_last_error("ERROR: bad operator found when processing ','");
                return undef;
            }
            if (scalar(@{$opn_stack}) != scalar(@{$opr_stack}) + 2) {
                $self->set_last_error("ERROR: bad number of operands processing ','");
                return undef;
            }

            my @args = ();
            while (scalar(@{$opn_stack}) > 0) {
                unshift @args, pop @{$opn_stack};
            }
            while (scalar(@{$opr_stack}) > 0) {
                pop @{$opr_stack};
            }
            push @{$opn_stack}, [ '*LIST*', @args ];
            return 1;
        };

        # unary operators
        /^!$/ && do { $nargs = 1; last; };
        /^-u$/ && do { $nargs = 1; last; };

        # other operators are binary
        $nargs = 2;
    }

    #print Dumper($opn_stack);
    if (scalar(@{$opn_stack}) < $nargs) {
        $self->set_last_error("ERROR: too few operands for '$opr'");
        return undef;
    }

    my @args = ();
    while ($nargs-- > 0) {
        unshift @args, pop @{$opn_stack};
    }
    push @{$opn_stack}, [ $opr, @args ];
    return 1;
}

# This is the real expression reader.  If $read_until_paren is true,
# reads until a closing parenthesis is reached, else read until end of
# input.
sub _read_expr
{
    my $self = shift;
    my $read_until_paren = shift;

    my @opr_stack = ();
    my @opn_stack = ();

    my $last_is_opr = 1;
    while (42) {
        my $tok = $self->read_token();

        # check end of expression
        if (! defined($tok)) {
            if ($read_until_paren) {
                $self->set_last_error("ERROR: expecting ')', found end of expression");
                return undef;
            }
            last;
        }

        # closing paren: end expression?
        if ($tok eq ')') {
            last if ($read_until_paren);
            $self->set_last_error("ERROR: unexpected ')' in expression");
            return undef;
        }

        # read sub-exression
        if ($tok eq '(') {
            $tok = $self->_read_expr(1);
            return undef unless (defined($tok));
        }

        # process operand
        if (! (ref($tok) eq '' && $op_tokens{$tok})) {
            if (! $last_is_opr) {
                my $opn = pop @opn_stack;
                #push @opn_stack, [ '*CALL*', $opn, $tok ];
                if (ref($tok) eq 'ARRAY' && $tok->[0] eq '*LIST*') {
                    # transform list into arguments
                    my $nargs = scalar(@{$tok});
                    push @opn_stack, [ $opn, @{$tok}[1..$nargs-1] ];
                } else {
                    # unary function
                    push @opn_stack, [ $opn, $tok ];
                }
            } else {
                push @opn_stack, $tok;
            }
            $last_is_opr = 0;
            next;
        }
        
        if ($tok eq '-' && $last_is_opr) {
            $tok = '-u';  # consider it an unary '-'
        }

        # resolve expressions until precedence is ok
        while (scalar(@opr_stack) > 0) {
            my $st_opr = $opr_stack[scalar(@opr_stack)-1];
            if ($op_assoc_right{$tok}) {
                #print "RIGHT: $st_opr vs $tok\n";
                last if ($op_prec{$st_opr} <= $op_prec{$tok});
            } else {
                #print "LEFT : $st_opr vs $tok\n";
                last if ($op_prec{$st_opr} < $op_prec{$tok});
            }
            if (! $self->_combine_stack(\@opr_stack, \@opn_stack)) {
                return undef;
            }
        }

        push @opr_stack, $tok;
        $last_is_opr = 1;
    }

    # resolve everything
    while (scalar(@opr_stack) > 0) {
        if (! $self->_combine_stack(\@opr_stack, \@opn_stack)) {
            return undef;
        }
    }

    if (scalar(@opn_stack) == 0) {
        #$self->set_last_error("no expression");
        #return undef;
        return [ '*LIST*' ];
    }

    if (scalar(@opn_stack) != 1) {
        $self->set_last_error("ERROR: too many operands at end of expression");
        return undef;
    }
    return $opn_stack[0];
}

# Read an expression from the input.  Return [<cc>]undef[</cc>] on
# error (and set the last error to a string containing the error
# reason) or the expression tree that was read.
sub read_expr
{
    my $self = shift;

    return $self->_read_expr(0);
}

1;
