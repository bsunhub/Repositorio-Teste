#
# Copyright (C) 2007 Next Internet Solutions.
#
# Nextis::HTMLMail - a Perl package to generate HTML emails.
#

package Nextis::HTMLMail;

# This module generates HTML emails.

use strict;
use Carp;
use Data::Dumper;

use Fcntl;
use MIME::Base64;
use Digest::MD5;

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

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{'attachments'} = [];
    $self->{'content_text'} = '';
    $self->{'content_html'} = '';
    $self->{'out'} = '';
    bless($self, $class);

    return $self;
}

sub _gen_cid
{
    my $self = shift;

    return Digest::MD5::md5_hex($$ . time() . rand());
}

sub _gen_boundary
{
    my $self = shift;

    return '=' . $self->_gen_cid();
}

sub add_attachment
{
    my $self = shift;
    my $filename = shift;
    my $name = shift;
    my $content_type = shift;
    my $cid = shift;

    if (! defined($cid)) {
        my $ext = $filename;
        $ext =~ s/^.*(\.[^\.]+)$/$1/;
        $cid = $self->_gen_cid() . $ext;
    }

    push @{$self->{'attachments'}}, {
        'filename' => $filename,
        'name' => $name,
        'content_type' => $content_type,
        'cid' => $cid,
    };
    return $cid;
}

sub set_text
{
    my $self = shift;
    my $text = shift;

    $self->{'content_text'} = $text;
    return 1;
}

sub set_html
{
    my $self = shift;
    my $html = shift;

    $self->{'content_html'} = $html;
    return 1;
}

sub _out
{
    my $self = shift;
    my $text = shift;

    $self->{'out'} .= $text;
    return 1;
}

sub _out_header
{
    my $self = shift;
    my $name = shift;
    my $data = shift;

    $self->_out("$name: $data\n");
    return 1;
}

sub _out_file
{
    my $self = shift;
    my $filename = shift;

    my $fh = undef;
    if (! sysopen($fh, $filename, O_RDONLY)) {
        die "Can't open '$filename': $!";
    }
    while (42) {
        my $data = undef;
        my $len = 0;
        while ($len < 57) {
            my $read_len = sysread($fh, $data, 57 - $len, $len);
            if (! defined($read_len)) {
                close($fh);
                die "Can't read from '$filename': $!";
            }
            last if ($read_len == 0);
            $len += $read_len;
        }
        
        $self->_out(encode_base64($data));
        last if ($len < 57);
    }
    close($fh);
    return 1;
}

sub generate
{
    my $self = shift;
    my $from = shift;
    my $to = shift;
    my $cc = shift;
    my $subject = shift;

    my $boundary = $self->_gen_boundary();
    my $html_boundary = $self->_gen_boundary();
    $self->{'out'} = '';

    $cc = [] unless defined($cc);

    # global headers
    $self->_out_header('From', $from);
    $self->_out_header('To', $to);
    for my $cc (@{$cc}) {
        $self->_out_header('Cc', $cc);
    }
    $self->_out_header('Subject', $subject);
    $self->_out_header('Content-Type', "multipart/alternative;\n boundary=\"$boundary\"");
    $self->_out("\n");

    # text
    $self->_out("--$boundary\n");
    $self->_out_header('Content-Type', "text/plain; charset=us-ascii");
    $self->_out_header('Content-Transfer-Encoding', "7bit");
    $self->_out("\n");
    $self->_out("$self->{'content_text'}\n");
    $self->_out("\n");

    # html header
    $self->_out("--$boundary\n");
    $self->_out_header('Content-Type', "multipart/related;\n boundary=\"$html_boundary\"");
    $self->_out("\n");

    # html body
    $self->_out("--$html_boundary\n");
    $self->_out_header('Content-Type', "text/html");
    $self->_out("\n");
    $self->_out("$self->{'content_html'}\n");
    $self->_out("\n");

    # attachments
    for my $attach (@{$self->{'attachments'}}) {
        $self->_out("--$html_boundary\n");
        $self->_out_header('Content-Type', "$attach->{'content_type'}; name=\"$attach->{'name'}\"");
        $self->_out_header('Content-Transfer-Encoding', "base64");
        $self->_out_header('Content-ID', "<$attach->{'cid'}>");
        $self->_out_header('Content-Disposition', "inline; filename=\"$attach->{'name'}\"");
        $self->_out("\n");
        $self->_out_file($attach->{'filename'});
        $self->_out("\n");
    }
    $self->_out("--$html_boundary--\n");
    $self->_out("\n");
    $self->_out("--$boundary--\n");

    return $self->{'out'};
}

sub generate_old
{
    my $self = shift;
    my $from = shift;
    my $to = shift;
    my $subject = shift;

    my $boundary = $self->_gen_boundary();
    $self->{'out'} = '';

    # global headers
    $self->_out_header('From', $from);
    $self->_out_header('To', $to);
    $self->_out_header('Subject', $subject);
    $self->_out_header('Content-Type', "multipart/alternative; boundary=\"$boundary\"");
    $self->_out("\n");

    # text
    $self->_out("--$boundary\n");
    $self->_out_header('Content-Type', "text/plain; charset=\"iso-8859-1\"");
    $self->_out_header('Content-transfer-encoding', "8bit");
    $self->_out("\n");
    $self->_out("$self->{'content_text'}\n");
    $self->_out("\n");

    # html header
    $self->_out("--$boundary\n");
    $self->_out_header('Content-Type', "text/html");
    $self->_out_header('Content-transfer-encoding', "8bit");
    $self->_out("\n");
    $self->_out("$self->{'content_html'}\n");
    $self->_out("\n");

    # attachments
    for my $attach (@{$self->{'attachments'}}) {
        $self->_out("--$boundary\n");
        $self->_out_header('Content-Type', "$attach->{'content_type'}; name=\"$attach->{'name'}\"");
        $self->_out_header('Content-Transfer-Encoding', "base64");
        $self->_out_header('Content-ID', "<$attach->{'cid'}>");
        $self->_out_header('Content-Disposition', "inline; filename=\"$attach->{'name'}\"");
        $self->_out("\n");
        $self->_out_file($attach->{'filename'});
        $self->_out("\n");
    }
    $self->_out("--$boundary--\n");
    $self->_out("\n");

    return $self->{'out'};
}

1;
