#!/usr/bin/perl

# simple HTTP API daemon
# принимает POST запрос по адресу http://host:port/search
# выполняет поиск по адресу и возвращает результат списокм строк в простом параграфе <p></p>

use strict;
use warnings;
use Fcntl;

use Maillog::Error;
use Maillog::Logger qw(log);
use Maillog::Api;
use Conf;

use CGI qw();

my $conf = $Conf::Conf->{api};

main();

sub main {

    # Проверим необходимые параметры
    for my $key (qw(pid)) {
        defined $conf->{$key} or die "ERROR: mandatory parameter $key is not set";
    };

    # форк, просто чтобы не висеть в терминале
    my $pid = fork();
    defined $pid or die "ERROR: unable to fork: $!\n";

    # Родитель
    if ($pid) {
        # пишем пид
        sysopen(PIDFILE, $conf->{pid}, O_WRONLY | O_EXCL | O_CREAT) or do
        {
            log("ERROR: unable to create pid file $conf->{pid}: $!");
            kill TERM => $pid;
            exit 1;
        };
        print PIDFILE $pid;
        close PIDFILE;

        exit 0;
    }

    # Дочерний процесс
    api();

} # main

sub api {

    # лог файл
    # открываем, если задан
    my $err = Maillog::Logger::open_log($conf->{log});
    $err and $err ne E_NO_ERROR and do {
        log("unable to open log file $conf->{log}:", log_hash($err));
        finish();
    };

    # Сигналы
    $SIG{USR1} = sub {
        $err = Maillog::Logger::rotate_log($conf->{log});
        $err and $err ne E_NO_ERROR and do {
            log("rotate_log failed:", log_hash($err));
            finish();
        };
    };

    $SIG{TERM} = sub {
        finish();
    };

    my $api;
    ($api, $err) = Maillog::Api->new({conf => $Conf::Conf->{api}, db_conf => $Conf::Conf->{database}});
    $err and $err ne E_NO_ERROR and do {
        log("unable to create Api object:", log_hash($err));  
        finish();
    };

    $api->run();
    finish();
} # api

sub finish {
    -e $conf->{pid} and do {
        unlink($conf->{pid}) or log("ERROR: unable to unlink pid file $conf->{pid}: $!");
    };
    log("Finished");
    exit 0;
} # finish
