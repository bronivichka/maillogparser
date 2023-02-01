package Maillog::Logger;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(log log_hash);

sub log {

    print STDERR join(" ", @_), "\n";

} # log

sub log_hash {
    my ($hash) = @_;

    $hash and %$hash or return;
    return join(', ', map { "$_ => " . ($hash->{$_} || '') } keys %$hash);

} # log_hash

1;
