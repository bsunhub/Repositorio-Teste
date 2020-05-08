
package Util;

use strict;
use warnings;

sub read_file
{
    my $filename = shift;

    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        print "ERRO: impossivel ler '$filename': $!\n";
        return undef;
    }
    my $out = '';
    while (<$fh>) {
        s/\r//g;
        $out .= $_;
    }
    close($fh);
    return $out;
}

sub run_command
{
    my $cmd = shift;
    my $really_run = shift;

    if (! $really_run) {
        return {
            'ok' => 1,
            'code' => 0,
            'cmd' => $cmd,
            'msg' => "Nao executado",
            'out' => '',
        };
    }

    my $fh = undef;
    if (! open($fh, '-|', "$cmd 2>&1")) {
        return {
            'ok' => 0,
            'code' => -1,
            'cmd' => $cmd,
            'msg' => "Impossivel executar comando: $!",
            'out' => '',
        };
    }
    my $out = '';
    while (<$fh>) {
        s/\r//g;
        $out .= $_;
    }
    close($fh);
    my $st = $?;
    my $code = $st >> 8;
    return {
        'ok' => ($code == 0) ? 1 : 0,
        'code' => $code,
        'cmd' => $cmd,
        'msg' => "Terminado com codigo '$code'",
        'out' => $out,
    };        
}

sub cmd_report
{
    my $r = shift;

    my $out = '';
    $out .= "------------------------------------\n";
    $out .= "COMANDO: $r->{'cmd'}\n";
    $out .= "CODIGO DE SAIDA: $r->{'code'}\n";
    $out .= "EXECUCAO: $r->{'msg'}\n";
    $out .= "SAIDA:\n";
    $out .= $r->{'out'};
    $out .= "------------------------------------\n";
    return $out;
}

sub map_domain_name
{
    my $map = shift;
    my $type = shift;
    my $old_domain = shift;
    my $old_name = shift;

    $type = lc($type);
    $old_domain = lc($old_domain);
    $old_name = lc($old_name);

    # map domain
    my $new = undef;
    if (exists($map->{$type})) {
        my $i = $map->{'old_domains'}->{$old_domain};
        if (defined($i) && exists($map->{$type}->{'trans'}->[$i]->{$old_name}) && $map->{$type}->{'trans'}->[$i]->{$old_name} ne '') {
            $new = $map->{'new_domain'} . "\\" . $map->{$type}->{'trans'}->[$i]->{$old_name};
        }
    }
    return $new;
}

sub read_map
{
    my $filename = shift;

    # read file
    my $fh = undef;
    if (! open($fh, '<', $filename)) {
        die "ERRO: impossivel abrir arquivo '$filename': $!";
    }
    my $map = {};
    my $first = 1;
    while (<$fh>) {
        s/\r//g;
        chomp;
        my $line = $_;
        next if ($line =~ /^\s*$/);
        my ($type, $new, @old) = split(/,/, $line);
        if (! defined($type) || ! defined($new) || scalar(@old) == 0) {
            next;
        }
        my @src = ($new, @old);
        if ($first) {
            $map->{'new_domain'} = $new;
            $map->{'old_domains'} = {};
            for my $i (0..scalar(@src)-1) {
                $map->{'old_domains'}->{lc($src[$i])} = $i;
            }
            $map->{'trans'} = [ {} x scalar(@src) ];
            $first = 0;
        } else {
            $map->{lc($type)} = {} unless defined($map->{lc($type)});
            for my $i (0..scalar(@src)-1) {
                $map->{lc($type)}->{'trans'}->[$i]->{lc($src[$i])} = $new;
            }
        }
    }
    close($fh);

    return $map;
}

sub read_vobs
{
    my $vobs_file = shift;

    my $txt = undef;
    if (defined($vobs_file)) {
        $txt = read_file($vobs_file);
        return undef unless defined($txt);
    } else {
        my $ret = run_command("cleartool lsvob", 1);
        if (! $ret->{'ok'}) {
            print "ERRO: impossivel listar VOBs:\n";
            print cmd_report($ret);
            return undef;
        }
        $txt = $ret->{'out'};
    }

    my $vobs = {};
    my @out = split(/\n/, $txt);
    for my $line (@out) {
        if ($line !~ /^\*?\s+(\\[^\s]+)\s+([^\s+]+)\s+(.*)$/) {
            next;
        }
        my ($tag, $path, $extra) = ($1, $2, $3);
        my $vob = {
            'tag' => $tag,
            'path' => $path,
            'extra' => $extra,
        };
        $vobs->{$tag} = $vob;
    }
    return $vobs;
}

sub read_vobs_alt_format
{
    my $vobs_file = shift;

    my $txt = read_file($vobs_file);

    my $vobs = {};
    my $cur_vob = undef;
    my @out = split(/\n/, $txt);
    for my $line (@out) {
        if ($line =~ /^Tag:\s*([^\s]+)\s*$/) {
            my $vob_tag = $1;
            $cur_vob = {
                'tag' => $vob_tag
            };
            $vobs->{$cur_vob->{'tag'}} = $cur_vob;
            next;
        }
        if ($line =~ /^\s*([^:]+)\s*:\s*(.*?)\s*$/) {
            my ($name, $val) = ($1, $2);
            $name =~ s/[^A-Za-z0-9_]/_/g;
            $name = "*" . lc($name);
            if (defined($cur_vob)) {
                $cur_vob->{$name} = $val;
            }
            next;
        }
    }

    my $copy_vob_var = sub {
        my $vob = shift;
        my $from = shift;
        my $to = shift;

        if (exists($vob->{$from})) {
            $vob->{$to} = $vob->{$from};
        }
    };

    for my $tag (keys %{$vobs}) {
        my $vob = $vobs->{$tag};
        $copy_vob_var->($vob, '*global_path', 'path');
        $copy_vob_var->($vob, '*vob_server_access_path', 'server_path');
        $copy_vob_var->($vob, '*vob_on_host', 'host');
    }

    return $vobs;
}

1;
