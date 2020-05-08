
package Nextis::SexpTokenRead;

use strict;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    $self->{'input'} = undef;
    $self->{'pos'} = 0;
    bless($self, $class);

    my $val = shift;

    $self->{'input'} = $val if (defined($val));

    return $self;
}

sub reset
{
    my $self = shift;
    my $input = shift;

    $self->{'input'} = $input;
    $self->{'pos'} = 0;
}

sub look
{
    my $self = shift;
    my $len = shift || 1;

    return substr($self->{'input'}, $self->{'pos'}, $len);
}

sub get
{
    my $self = shift;
    my $len = shift || 1;

    my $str = substr($self->{'input'}, $self->{'pos'}, $len);
    $self->{'pos'} += $len;
    if ($self->{'pos'} > length($self->{'input'})) {
        $self->{'pos'} = length($self->{'input'}) + 1;
    }
    return $str;
}

sub unget
{
    my $self = shift;
    my $len = shift || 1;

    $self->{'pos'} -= $len;
    if ($self->{'pos'} < 0) {
        $self->{'pos'} = 0;
    }
    return 0;
}

sub read_token
{
    my $self = shift;

    my $ch;
    do {
	do {
	    $ch = $self->get();
	} while (length($ch) > 0 && $ch =~ /\s/);
	if (length($ch) == 0) {
	    return undef;
	}
	if ($ch eq ';') {
	    do {
		$ch = $self->get();
	    } while (length($ch) > 0 && $ch ne "\n");
	    $ch = ';';
	}
    } while ($ch eq ';');

    if ($ch eq '(' || $ch eq ')' || $ch eq "'") {
        return $ch;
    }

    if ($ch eq '"') {
	my $str = '"';

        my $last_is_slash = 0;
	while (42) {
	    $ch = $self->get();
	    return undef if (length($ch) == 0);
            if ($last_is_slash) {
                $last_is_slash = 0;
            } else {
                if ($ch eq '\\') {
                    $last_is_slash = 1;
                    next;
                }
                last if ($ch eq '"');
            }
	    $str .= $ch;
	}
	$str .= '"';
        #print STDERR "RETURN '$str'\n";
	return $str;
    }

    my $str = $ch;
    while (42) {
        $ch = $self->get();
        if (length($ch) == 0 || $ch =~ /[\s\(\)\']/) {
            $self->unget();
            last;
        }
        $str .= $ch;
    }
    return $str;
}

package Nextis::Sexp;

use strict;
use FileHandle;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = qw(&read_sexps &read_sexps_from_file &print_sexp);
    %EXPORT_TAGS = qw();
    @EXPORT_OK   = qw();
}
our @EXPORT_OK;

sub _read_sexp
{
    my $reader = shift;

    my $tok = $reader->read_token();
    return undef unless defined($tok);

    if ($tok eq ')') {
        return ')';
    }

    if ($tok eq '(') {
        my $l = [];
        while (defined($tok = _read_sexp($reader)) && $tok ne ')') {
            push(@{$l}, $tok);
        }
        return $l;
    }

    if ($tok =~ /^[0-9\.]/) {
        return $tok;
    }
    if ($tok =~ /^\"/) {
        $tok =~ s/^\"//;
        $tok =~ s/\"$//;
        return $tok;
    }
    return $tok;
};

sub read_sexps
{
    my $input = shift;

    my $reader = new Nextis::SexpTokenRead($input);
    my @file = ();
    my $sexp;
    while (42) {
	$sexp = _read_sexp($reader);
	last unless defined($sexp);
	push @file, $sexp;
    }
    return \@file;
}

sub read_sexps_from_file
{
    my $filename = shift;

    my $fh = new FileHandle;
    if (! open($fh, "<$filename")) {
	return undef;
    }
    local $/ = undef;
    my $input = <$fh>;
    close($fh);

    return read_sexps($input);
}

sub print_sexp
{
    my $sexp = shift;

    if (ref($sexp) ne 'ARRAY') {
	print $sexp;
	return;
    }
    print '(';
    for (my $i = 0; $i < scalar(@{$sexp}); $i++) {
	print_sexp($sexp->[$i]);
	if ($i < scalar(@{$sexp})-1) {
	    print ' ';
	}
    }
    print ')' . "\n";
};

1;
