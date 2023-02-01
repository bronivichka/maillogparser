#!/usr/bin/perl

# maillog parser

use strict;
use warnings;
use Maillog::Parser;
use Maillog::Error;
use Maillog::Logger qw(log print_error);
use Maillog::Database;
use Conf;

use Data::Dumper;

@ARGV >= 1 or usage();
my $file = shift;

my $parser;
my $dbh;
my $err;

main();

sub main {
    $parser = Maillog::Parser->new({conf => $Conf::Conf->{parser}});

    ($dbh, $err) = Maillog::Database->new($Conf::Conf->{database});
    $err and $err ne E_NO_ERROR and do {
        print_error($err);
        exit 1;
    };

    $err = $parser->open($file);
    $err and $err ne E_NO_ERROR and do {
        print_error($err);
        exit 1;
    };

    while ($err = $parser->parse()) {
        $dbh->set_stamp_borders($parser->{begin_stamp}, $parser->{end_stamp});
        $dbh->insert_message_data($parser->{msg});
        $dbh->insert_log_data($parser->{log});
        $dbh->set_stamp_borders();
        last if $err eq E_EOF;
    }
    $parser->close();
}

# print usage message and exit
sub usage {

    print STDERR "\nusage: $0 </path/to/maillog/file>\n\n";
    exit 0;

} # usage
