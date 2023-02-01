package Conf;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw($Conf);

our $Conf = {
    database => {
        dbname => "maillog",
        user => "maillog",
        password => "",
        host => "localhost",
    },

    parser => {
        chunk_size => 999,
    },

};

1;
