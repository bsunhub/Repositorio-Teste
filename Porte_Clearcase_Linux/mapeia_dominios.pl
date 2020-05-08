#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Util;
use Nextis::Config;
use Nextis::CommandLine;

my $config = {
    # Usuario/grupo usados quando o mapeamento nao existe
    'default' => {
        'user' => 'ADMINISTRADOR_DO_CLEARCASE',
        'group' => 'GRUPO_ADMINISTRADOR',
    },

    'out_file' => undef,
};

sub map_name
{
    my $map = shift;
    my $old = shift;
    my $type = shift;

    if (lc($old) eq 'account unknown') {
        return undef;
    }

    if ($old !~ /^([^\\]+)\\(.*)$/) {
        print "*** AVISO: nome invalido: '$old'\n";
        return undef;
    }
    my ($old_domain, $old_name) = ($1, $2);

    my $new = Util::map_domain_name($map, $type, $old_domain, $old_name);

    if (! defined($new)) {
        print "*** AVISO: nao foi encontrado mapeamento para '$old' (tipo:'$type')\n";
        return undef;
    }
    return $new;
}

sub translate_vob_domains
{
    my $in = shift;
    my $out = shift;
    my $map = shift;

    # translate
    my $ok = 1;
    while (<$in>) {
        s/\r//g;
        chomp;
        my $linha = $_;
        my @items = split(/,/, $linha);
        if (scalar(@items) < 4) {
            print $out "$linha\n";
            next;
        }
        my $new_name = map_name($map, $items[0], $items[1]);
        if (! defined($new_name)) {
            my $def = $config->{'default'}->{lc($items[1])};
            $new_name = "$map->{'new_domain'}\\$def";
            $ok = 0;
        }
        print "- '$items[0]' -> '$new_name'\n";
        my @out_row = ($items[0], $items[1], $items[2], $new_name);
        print $out join(",", @out_row) . "\n";
    }

    return $ok;
}

sub map_vob_domains
{
    my $map = shift;
    my $vob = shift;

    my $in_dom_file = "$vob->{'path'}$vob->{'tag'}_siddump.csv";
    my $out_dom_file = $config->{'out_file'};
    if (! defined($out_dom_file)) {
        $out_dom_file = "$vob->{'path'}$vob->{'tag'}_sidmap.csv";
    }

    # open input file
    my $in = undef;
    if (! open($in, '<', $in_dom_file)) {
        print "ERRO: impossivel ler '$in_dom_file': $!\n";
        return undef;
    }

    # open output file
    my $out = undef;
    if (! open($out, '>', $out_dom_file)) {
        print "ERRO: impossivel escrever '$out_dom_file': $!\n";
        close($out);
        return undef;
    }

    my $ok = translate_vob_domains($in, $out, $map);

    # close files
    close($in);
    close($out);

    return $ok;
}

sub map_file
{
    my $map = shift;
    my $in_file = shift;

    my $out_file = $config->{'out_file'};
    if (! defined($out_file)) {
        print "Por favor especifique o arquivo de saida com '-o'.\n";
        exit(1);
    }

    my $in = undef;
    if (! open($in, '<', $in_file)) {
        die "ERRO: impossivel abrir '$in_file': $!";
    }
    my $out = undef;
    if (! open($out, '>', $out_file)) {
        die "ERRO: impossivel abrir '$out_file': $!";
    }

    my $ok = translate_vob_domains($in, $out, $map);

    close($in);
    close($out);

    return $ok;
}

sub print_help
{
    print <<"EOH"
$0 [options] [VOBS...]

options:
  -h              mostra este texto
  -map ARQ        usa o mapa de usuarios do arquivo ARQ
  -vob-list ARQ   usa arquivo com a saida do lsvob ao inves de rodar lsvob
  -i ARQ          le entrada de ARQ ao inves de arquivo no diretorio da VOB
  -o ARQ          escreve saida em ARQ ao inves de arquivo no diretorio da VOB
  VOBS...         processa somente as VOBs listadas
EOH
;
}

sub main
{
    my @args = @_;

    my $opts = parse_cmdline(\@args, [ '-h', '-map=', '-vob-list=', '-i=', '-o=' ]);
    if ($opts->{'h'}) {
        print_help();
        return 0;
    }
    $config->{'out_file'} = $opts->{'o'};
    my $in_file = $opts->{'i'};
    my $map_file = $opts->{'map'};
    my $vobs_list_file = $opts->{'vob-list'};
    my $spec_vobs = $opts->{'_'};

    if (! defined($map_file)) {
        print "Por favor especifique um arquivo com o mapeamento dos usuarios\n";
        print "(use -h para a lista de opcoes)\n";
        return 1;
    }

    # le mapa de dominios
    my $map = Util::read_map($map_file);

    # processa apenas um arquivo
    if (defined($in_file)) {
        my $ok = map_file($map, $in_file);
        return ($ok) ? 0 : 1;
    }

    # le VOBs do ClearCase
    my $vobs = Util::read_vobs($vobs_list_file);

    # seleciona VOBs para mapear
    my @sel_vobs = ();
    if (scalar(@{$spec_vobs}) == 0) {
        @sel_vobs = sort keys %{$vobs};
    } else {
        my $ok = 1;
        for my $tag (@{$spec_vobs}) {
            if (! exists($vobs->{$tag})) {
                print "ERRO: vob '$tag' nao encontrada\n";
                $ok = 0;
            } else {
                push @sel_vobs, $tag;
            }
        }
        if (! $ok) {
            exit(1);
        }
    }
    
    # exporta VOBs selecionadas
    for my $tag (@sel_vobs) {
        map_vob_domains($map, $vobs->{$tag});
    }
    return 0;
}

exit main(@ARGV);
