package Maillog::Logger;

# Самый простой логгер в STDOUT, с минимальным форматированием строк

use strict;
use warnings;
use Maillog::Error;
use Exporter 'import';

our @EXPORT_OK = qw(log log_hash print_error);

sub log {

    print STDERR join(" ", @_), "\n";

} # log

sub log_hash {
    my ($hash) = @_;

    $hash and %$hash or return;
    return join(', ', map { "$_ => " . ($hash->{$_} || '') } keys %$hash);

} # log_hash

# Открываем лог файл и перенаправляем вывод в него
sub open_log {
    my ($file) = @_;

    # Если лог файл не задан, ничего не делаем и не возвращаем ошибку
    $file or return E_NO_ERROR;

    open (STDOUT, '>>', $file) or return error(ECODE_FILE_ERROR, $!);
    open (STDERR, '>>', $file) or return error(ECODE_FILE_ERROR, $!);

    return E_NO_ERROR;

} # open_log

# ротация лога
# если лог файл не задан - нечего и ротировать
sub rotate_log {
    my ($log) = @_;

    $log or return E_NO_ERROR;

    close STDERR;
    close STDOUT;
    open (STDOUT, '>>', $log) or return error(ECODE_FILE_ERROR, $!);
    open (STDERR, '>>', $log) or return error(ECODE_FILE_ERROR, $!);
    select STDERR;
    $| = 1;
    select STDOUT;
    &log("Reopened logfile $log");

    return E_NO_ERROR;

} # rotate_log

sub print_error {
    my $error = shift;

    $error and %$error or return;
    $error->{code} or return;
    $error->{message} ||= "";

    &log("ERROR: code $error->{code} message $error->{message}");
} # print_error

1;
