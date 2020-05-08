#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Util;
use Nextis::Logger;
use Nextis::Config;
use Nextis::CommandLine;

my $default_config_file = 'config.cfg';

my $log = new Nextis::Logger();
my $config = {
    'really_do' => 0,
    'global_vars' => {},
};

sub get_vob_command_line
{
    my $cmd = shift;
    my $vob = shift;

    my $data = { %{$config->{'global_vars'}} };

    my $vob_tag = $vob->{'tag'};
    my $vob_path = $vob->{'path'};
    my $vob_host = $vob->{'host'};
    my $vob_server_path = $vob->{'server_path'};

    my $vob_path_dirs = $vob_path;
    $vob_path_dirs =~ s/\//\\/g;
    my @vob_dirs = split(/\\/, $vob_path_dirs);

    $vob_tag =~ s/\\//g;
    $data->{'vob_tag'} = $vob_tag;
    $data->{'vob_path'} = (defined($vob_path)) ? $vob_path : '';
    $data->{'vob_dir'} = $vob_dirs[scalar(@vob_dirs)-1];
    $data->{'vob_host'} = (defined($vob_host)) ? $vob_host : '';
    $data->{'vob_server_path'} = (defined($vob_server_path)) ? $vob_server_path : '';
    
    my $cmdline = $cmd->{'cmd'};
    $cmdline =~ s/\${(.*?)}/defined($data->{lc($1)}) ? $data->{lc($1)} : ''/ge;
    return $cmdline;
}

sub format_time
{
    my $t = shift;

    my $hour = int($t / 60/60);
    my $min = int($t / 60) % 60;
    my $sec = int($t) % 60;
    return sprintf("%02d:%02d:%02d", $hour, $min, $sec);
}

sub process_vob
{
    my $vob = shift;
    my $cmds = shift;

    print "\n";
    print "---------------------------------\n";
    print "Processando vob '$vob->{'tag'}'\n";

    $log->log('NOTICE', '');
    $log->log('NOTICE', "================================================");
    $log->log('NOTICE', "== Processando vob '$vob->{'tag'}'");

    my $found_error = 0;
    my $start_time = time();
    for my $i (0..scalar(@{$cmds})-1) {
        my $cmd = $cmds->[$i];
        my $num = $i+1;
        my $cmdline = get_vob_command_line($cmd, $vob);

        if ($found_error && ! $cmd->{'force'}) {
            $log->log('NOTICE', "-> Ignorando execucao do comando '$cmdline'");
            next;
        }

        print "-> [$num] '$cmdline'\n";
        my $res = Util::run_command($cmdline, $config->{'really_do'});
        if (! $cmd->{'ignore'}) {
            my $report = Util::cmd_report($res);
            $log->log('NOTICE', $report);
            if (! $res->{'ok'}) {
                print "ERRO executando comando:\n";
                print $report;
                $found_error = 1;
                if ($cmd->{'abort'}) {
                    $log->log('NOTICE', "-> Abortando execucao para VOB '$vob->{'tag'}'");
                    last;
                }
            }
        }
    }
    my $end_time = time();
    my $total_time = format_time($end_time - $start_time);

    print "-> Tempo de execucao para VOB '$vob->{'tag'}': $total_time\n";
    $log->log('NOTICE', "-> Tempo de execucao para VOB '$vob->{'tag'}': $total_time");

    return ($found_error) ? undef : 1;
}

sub get_vob_cmds
{
    my $cfg = shift;

    my $sec = $cfg->get_section('vob_commands');
    if (! defined($sec)) {
        print "ERRO: arquivo de configuracao nao tem secao 'vob_commands'\n";
        return undef;
    }
    my $cmds = [];
    for (my $i = 1; exists($sec->{"cmd$i"}); $i++) {
        my $cmd = $sec->{"cmd$i"};
        my $force_exec = ($sec->{"cmd${i}_force_exec"}) ? 1 : 0;
        my $abort_on_error = ($sec->{"cmd${i}_abort_on_error"}) ? 1 : 0;
        my $ignore_error = ($sec->{"cmd${i}_ignore_error"}) ? 1 : 0;
        push @{$cmds}, {
            'cmd' => $cmd,
            'force' => $force_exec,
            'abort' => $abort_on_error,
            'ignore' => $ignore_error,
        };
    }
    return $cmds;
}

sub print_help
{
    print <<"EOH"
$0 [opcoes] [VOBS...]

opcoes:
  -h              mostra este texto
  -r              executa comandos (default: apenas mostra o que seria feito)
  -cfg ARQ        usa o arquivo de configuracao ARQ (default: $default_config_file)
  -vob-list ARQ   usa arquivo ARQ com a saida do lsvob ao inves de rodar lsvob
  -vob-list2 ARQ  usa arquivo ARQ (no formato novo) com a saida do lsvob ao inves de rodar lsvob
  VOBS...         processa somente VOBs especificadas (default: todas as VOBs)
EOH
;
}

sub main
{
    my @args = @_;
    
    my $opts = parse_cmdline(\@args, [ '-h', '-r', '-cfg=', '-vob-list=', '-vob-list2=' ]);
    if ($opts->{'h'}) {
        print_help();
        return 0;
    }
    my $spec_vobs = $opts->{'_'};
    my $vobs_list_file = $opts->{'vob-list'};
    my $vobs_list2_file = $opts->{'vob-list2'};
    my $cfg_file = $opts->{'cfg'};
    if (! defined($cfg_file)) {
        $cfg_file = $default_config_file;
    }
    if ($opts->{'r'}) {
        $config->{'really_do'} = 1;
    }

    # le arquivo de configuracao
    my $cfg = new Nextis::Config($cfg_file);
    if (! $cfg) {
        print "ERRO: impossivel ler arquivo de configuracao '$cfg_file'\n";
        exit(1);
    }
    my $vob_cmds = get_vob_cmds($cfg);
    if (! defined($vob_cmds)) {
        exit(1);
    }
    if ($cfg->section_exists('log')) {
        $log->set_config($cfg->get_section('log'));
    }
    if ($cfg->section_exists('variables')) {
        my $vars = $cfg->get_section('variables');
        for my $k (keys %{$vars}) {
            $config->{'global_vars'}->{lc($k)} = $vars->{$k};
        }
    }

    # le VOBs do ClearCase
    my $vobs = undef;
    if (defined($vobs_list2_file)) {
        $vobs = Util::read_vobs_alt_format($vobs_list2_file);
    } else {
        $vobs = Util::read_vobs($vobs_list_file);
    }
    return 1 unless defined($vobs);

    # seleciona VOBs para processar
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

    if (! $config->{'really_do'}) {
        print "**\n";
        print "** AVISO: executando em modo teste, nenhum comando sera executado\n";
        print "**\n";
    }

    # executa comandos nas VOBs selecionadas
    for my $tag (@sel_vobs) {
        process_vob($vobs->{$tag}, $vob_cmds);
    }
    return 0;
}

exit main(@ARGV);
