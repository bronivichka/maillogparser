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

    api => {
        host => "0.0.0.0",
        port => 8080,
        search_limit => 100,
        log => "/home/linas/maillogparser/log/api.log",
        pid => "/home/linas/maillogparser/tmp/api.pid",
    },
};

1;
