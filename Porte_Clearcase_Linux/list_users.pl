#!/usr/bin/perl

use strict;
use warnings;

my $list = {};

sub process_file
{
    my $filename = shift;

    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        print STDERR "ERRO lendo arquivo '$filename': $!\n";
        return undef;
    }
    while (<$fh>) {
        s/[\r\n]+//g;
        my @l = split(/,/, $_);
        next if (scalar(@l) < 3);
        my ($name, $type, $uuid) = @l;
        $list->{$type} = {} unless defined($list->{$type});
        $list->{$type}->{$name} = {} unless defined($list->{$type}->{$name});
        $list->{$type}->{$name}->{$uuid}++;
    }
    close($fh);
    return 1;
}

sub main
{
    my @files = @_;

    if (scalar(@files) == 0) {
        print STDERR "Erro: nenhum arquivo especificado! (use -h para ajuda)\n";
        return 0;
    }

    if (grep { $_ eq '-h' } @files) {
        print <<"END_HELP"
USO: $0 arquivos...
END_HELP
;
        return 0;
    }

    my @file_list = ();
    for my $spec (@files) {
        push @file_list, glob($spec);
    }
    for my $file (@file_list) {
        process_file($file);
    }

    for my $type ('USER', 'GROUP') {
        for my $name (sort keys %{$list->{$type}}) {
            for my $uuid (sort keys %{$list->{$type}->{$name}}) {
                print "$name,$type,$uuid\n";
            }
        }
        print "\n";
    }
}

exit main(@ARGV);
