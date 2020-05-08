#
# Copyright (C) 2005 Next Internet Solutions.
#
# Nextis::CCUtil - a Perl package with utility functions for ClearCase
# administration.
#

package Nextis::CCUtil;

use strict;
use Carp;

#our $AUTOLOAD;

BEGIN {
    use Exporter();
    #our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    $Nextis::CCUtil::VERSION     = 1.00;
    
    @Nextis::CCUtil::ISA         = qw(Exporter);
    @Nextis::CCUtil::EXPORT      = qw(cc_ls_vobs cc_get_vob_info cc_get_all_vobs_info);
    %Nextis::CCUtil::EXPORT_TAGS = qw();
    @Nextis::CCUtil::EXPORT_OK   = qw();
}

#our $cleartool_cmd;
$Nextis::CCUtil::cleartool_cmd = 'cleartool';

sub cc_ls_vobs
{
    my $filter = shift;
    my $filter_key = shift;

    my $output = qx{$Nextis::CCUtil::cleartool_cmd lsvob};
    
    my @vobs = ();
    my @out = split(/\n/, $output);
    my $line;
    for $line (@out) {
        chomp($line);
        next unless ($line);

        $line =~ s/^(.).//;
        my $mounted = $1;

        my ($tag, $path, $private, $ucm) = split(/[\s\t]+/, $line);
        $path = '' unless $path;
        $private = '' unless $private;
        $ucm = '' unless $ucm;

        my $vob = {
            'mounted' => ($mounted eq '*') ? 1 : 0,
            'tag' => $tag,
            'path' => $path,
            'private' => ($private eq 'private') ? 1 : 0,
            'ucm' => ($ucm eq '(ucmvob)') ? 1 : 0,
        };

        if (defined($filter) && ref($filter) eq 'CODE') {
            if (&{$filter}($vob)) {
                push @vobs, $vob;
            }
        } elsif (defined($filter) && ref($filter) eq '') {
            my $val = $vob->{$filter_key || 'tag'} || '';
            if ($val =~ /$filter/) {
                push @vobs, $vob;
            }
        } else {
            push @vobs, $vob;
        }
    }

    return \@vobs;
}

sub cc_get_vob_info
{
    my $tag = shift;

    my $vob = {};
    my $output = qx{$Nextis::CCUtil::cleartool_cmd lsvob -l $tag};
    my @output = split(/\n/, $output);
    my $line;
    for $line (@output) {
        chomp($line);
        my ($name, $value) = split(/\s*:\s*/, $line, 2);
        next if (! $name);

        $name = lc($name);
        $name =~ s/^\s+//g;
        $name =~ s/\s+$//g;
        $name =~ s/[^A-Za-z0-9_]/_/g;
        if ($name eq 'tag') {
            my $comment = $value;
            $comment =~ s/^.*\s+\"(.*)\"/$1/;
            $value =~ s/\s+\".*$//;
            $vob->{'comment'} = $comment;
        }
        $vob->{$name} = $value;
    }

    return $vob;
}

sub _cc_insert_vob
{
    my $vobs = shift;
    my $vob = shift;
    my $filter = shift;
    my $filter_key = shift;
    
    if (defined($filter) && ref($filter) eq 'CODE') {
        if (&{$filter}($vob)) {
            push @{$vobs}, $vob;
        }
    } elsif (defined($filter) && ref($filter) eq '') {
        my $val = $vob->{$filter_key || 'tag'} || '';
        if ($val =~ /$filter/) {
            push @{$vobs}, $vob;
        }
    } else {
        push @{$vobs}, $vob;
    }
}

sub cc_get_all_vobs_info
{
    my $filter = shift;
    my $filter_key = shift;

    my $output = qx{$Nextis::CCUtil::cleartool_cmd lsvob -l};

    my @vobs = ();
    my $cur_vob = {};

    my @lines = split(/\n/, $output);
    my $line;
    for $line (@lines) {
        chomp($line);
        my ($name, $value) = split(/\s*:\s*/, $line, 2);
        next if (! $name);

        $name = lc($name);
        $name =~ s/^\s+//g;
        $name =~ s/\s+$//g;
        $name =~ s/[^A-Za-z0-9_]/_/g;
        if ($name eq 'tag') {
            if ($cur_vob->{'tag'}) {
                _cc_insert_vob(\@vobs, $cur_vob, $filter, $filter_key);
            }
            my $comment = $value;
            $comment =~ s/^.*\s+\"(.*)\"/$1/;
            $value =~ s/\s+\".*$//;
            $cur_vob = { 'tag' => $value, 'comment' => $comment };
        } else {
            $cur_vob->{$name} = $value;
        }
    }
    if ($cur_vob->{'tag'}) {
        _cc_insert_vob(\@vobs, $cur_vob, $filter, $filter_key);
    }

    return \@vobs;
}

1;
