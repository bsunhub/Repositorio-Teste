#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Util;
use Nextis::Config;
use Nextis::CommandLine;

my $config = {
    'really_do' => 0,
    'vob_siddump' => "\"C:\\Program Files\\Rational\\ClearCase\\etc\\utils\\vob_siddump.exe\"",
};

sub export_vob_sids
{
    my $vob = shift;

    print "\n";
    print "---------------------------------\n";
    print "Exportando vob '$vob->{'tag'}'\n";

    my $ret = 1;

    # -- executa lock
    print "-> cleartool lock vob:$vob->{'tag'}\n";
    my $lock_cmd = Util::run_command("cleartool lock vob:$vob->{'tag'}", $config->{'really_do'});
    if (! $lock_cmd->{'ok'}) {
        print "Erro executando comando de lock\n";
        print Util::cmd_report($lock_cmd);
        return undef;
    }

    # -- exporta
    my $ok = eval {
        # siddump
        print "-> vob_siddump $vob->{'tag'} $vob->{'path'}$vob->{'tag'}_siddump.csv\n";
        my $siddump_cmd = Util::run_command("$config->{'vob_siddump'} $vob->{'tag'} $vob->{'path'}$vob->{'tag'}_siddump.csv", $config->{'really_do'});
        if (! $siddump_cmd->{'ok'}) {
            print "Erro executando comando de exportacao (vob_siddump)\n";
            print Util::cmd_report($siddump_cmd);
            die "-*- erro -*-";
        }

        1;
    };
    if (! $ok) {
        my $err = $@;
        $ret = undef;
        if ($err !~ /^-\*- erro -\*-/) {
            print "ERRO inesperado: $err\n";
        }
    }

    # -- executa unlock
    print "-> cleartool unlock vob:$vob->{'tag'}\n";
    my $unlock_cmd = Util::run_command("cleartool unlock vob:$vob->{'tag'}", $config->{'really_do'});
    if (! $unlock_cmd->{'ok'}) {
        print "Erro executando comando de unlock\n";
        print Util::cmd_report($unlock_cmd);
        return undef;
    }
    return $ret;
}

sub print_help
{
    print <<"EOH"
$0 [options] [VOBS...]

options:
  -h              mostra este texto
  -r              executar comandos (default: apenas mostrar o que seria feito)
  -vob-list ARQ   usa arquivo com a saida do lsvob ao inves de rodar lsvob
  VOBS...         processa somente as VOBs listadas
EOH
;
}

sub main
{
    my @args = @_;
    
    my $opts = parse_cmdline(\@args, [ '-h', '-r', '-vob-list=' ]);
    if ($opts->{'h'}) {
        print_help();
        return 0;
    }
    my $vobs_list_file = $opts->{'vob-list'};
    my $spec_vobs = $opts->{'_'};
    if ($opts->{'r'}) {
        $config->{'really_do'} = 1;
    }

    # le VOBs do ClearCase
    my $vobs = Util::read_vobs($vobs_list_file);
    return 1 unless defined($vobs);

    # seleciona VOBs para exportar
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
        export_vob_sids($vobs->{$tag});
    }
    return 0;
}

exit main(@ARGV);
