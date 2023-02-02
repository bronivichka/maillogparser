package Conf;

# Конфигурационный файл проекта
# секция database для доступа к БД (модуль Maillog::Database)
# секция parser для парсера (parser.pl)
# секция api для HTTP демона (Maillog::Api)

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw($Conf);

our $Conf = {
    # Параметры доступа к БД (postgresql)
    database => {
        dbname => "maillog",
        user => "maillog",
        password => "",
        host => "localhost",
    },

    # настройки парсера
    parser => {
        chunk_size => 999, # кол-во обрабатываемых за один раз строк
    },

    # настройки HTTP демона
    api => {
        host => "0.0.0.0",
        port => 8080,
        search_limit => 100, # максимальное кол-во строк в поиске
        log => "/home/linas/maillogparser/log/api.log",
        pid => "/home/linas/maillogparser/tmp/api.pid",
    },
};

1;
