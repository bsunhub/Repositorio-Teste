#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Util;

my $config = {
    # Usuario/grupo usados quando o mapeamento nao existe
    'default' => {
        'user' => 'ADMINISTRADOR_DO_CLEARCASE',
        'group' => 'GRUPO_ADMINISTRADOR',
    },
};

sub main
{
    my $map_file = shift;
    my $old = shift;
    my $resto = shift;

    if (! defined($map_file) || ! defined($old) || defined($resto)) {
        print "USO: $0 mapa.csv DOMINIO\\GRUPO\n";
        return 0;
    }

    # read map
    my $map = Util::read_map($map_file);

    # parse domain\\group
    my $new = undef;
    if (lc($old) ne 'account unknown') {
        if ($old !~ /^([^\\]+)\\(.*)$/) {
            print "*** AVISO: nome invalido: '$old'\n";
            return 1;
        }
        my ($old_domain, $old_name) = ($1, $2);
        
        $new = Util::map_domain_name($map, 'GROUP', $old_domain, $old_name);
    }
    if (! defined($new)) {
        #print "ERRO: nao foi encontrado mapeamento para grupo '$old'\n";
        $new = "$map->{'new_domain'}\\$config->{'default'}->{'group'}";
    }
    print "$new\n";
    return 0;
}

exit main(@ARGV);
