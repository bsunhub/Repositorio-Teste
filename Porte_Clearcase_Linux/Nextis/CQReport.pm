
package Nextis::CQReport;

use strict;
use Carp;

use Data::Dumper;

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

# Create a new [<cc>]Nextis::CQReport[</cc>].  You usually don't want
# to do this: you should use the [<cc>]Nextis::CQReporter[</cc>]'s
# method [<cc>]generate[</cc>] to generate this object.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $data = shift;

    $self->{'data'} = undef;
    bless($self, $class);

    $self->{'data'} = $data;

    return $self;
}

sub _xml_escape
{
    my $str = shift;

    return '' unless defined($str);

    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/\"/&quot;/g;
    $str =~ s/\'/&apos;/g;
    return $str;
}

sub do_dump
{
    my $x = shift;

    return "<![CDATA[" . Dumper($x) . "]]>";
}

sub _xml_error
{
    my $msg = shift;

    return "<?xml version=\"1.0\" encoding=\"iso-8859-1\" ?>\n"
	. "<error message=\"" . _xml_escape($msg) . "\" />\n";
}

sub _xml_get_field
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    my $xml = '';
    #$xml .= "<![CDATA[" . Dumper($value) . "]]>";

    if (ref($value) eq '') {
        $xml .= "<field name=\"" . _xml_escape($name) . "\" ";
        $xml .= "value=\"" . _xml_escape($value) . "\" />";
    } elsif (ref($value) eq 'HASH') {
        $xml .= $self->_xml_get_query($name, $value);
    } else {
        $xml .= "<field warning=\"bad type\" ";
        $xml .= "name=\"" . _xml_escape($name) . "\" ";
        $xml .= "value=\"" . _xml_escape($value) . "\" />";
    }

    return $xml;
}

sub _xml_get_query
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    if (ref($value) ne 'HASH') {
        return "<error>expecting hash, got '$value'</error>";
    }

    my $xml = "<Query name=\"" . _xml_escape($name) . "\">";

    $xml .= "<metadata>";
    for my $type ('start', 'end') {
        if (exists($value->{$type})) {
            my $item = $value->{$type};
            for my $f (@{$item->{'*order*'}}) {
                $xml .= $self->_xml_get_field($f, $item->{"\L$f"});
            }
        }
    }
    $xml .= "</metadata>";

    for my $item (@{$value->{'rows'}}) {
        $xml .= "<row>";
        for my $f (@{$item->{'*order*'}}) {
            $xml .= $self->_xml_get_field($f, $item->{"\L$f"});
        }
        $xml .= "</row>";
    }

    $xml .= "</Query>";

    return $xml;
}

# Return the report in a string in XML format.
sub get_xml_string
{
    my $self = shift;
    my $data = shift;
    my $opt = shift || {};

    my $encoding = $opt->{'encoding'} || '';
    my $xslt = $opt->{'stylesheet'} || '';

    my $xml;
    if ($encoding) {
        $xml = "<?xml version=\"1.0\" encoding=\"$encoding\" ?>\n";
    } else {
        $xml = '<?xml version="1.0" ?>' . "\n";
    }

    if ($xslt) {
        # use type="text/xsl" for IE
        $xml .= "<?xml-stylesheet type=\"application/xml\" href=\"$xslt\" ?>\n";
    }

    #print STDERR Dumper($self->{'data'});

    $xml .= "<report>";
    #$xml .= "<![CDATA[" . Dumper($self->{'data'}) . "]]>";
    for my $field (keys %{$self->{'data'}}) {
        $xml .= $self->_xml_get_query($field, $self->{'data'}->{$field});
    }
    $xml .= "</report>";
    return $xml;
}

1;
