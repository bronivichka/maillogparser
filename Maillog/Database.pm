package Maillog::Database;

use strict;
use warnings;
use DBI;
use Maillog::Error;
use Maillog::Logger qw(log log_hash);

use Data::Dumper;

sub new {
    my ($class, $conf) = @_;

    $conf and %$conf or return undef, error(ECODE_INVALID_PARAM, "database parameters are not set");
    my $self = {
        dbh => undef,
        conf => $conf,
        begin_stamp => undef,
        end_stamp => undef,
    };

    bless ($self, $class);

    # Сразу коннектимся к базе
    my $err = $self->connect_to_db();
    $err and $err ne E_NO_ERROR and return undef, $err;

    return $self, E_NO_ERROR

} # new

# коннект к базе данных
sub connect_to_db {
    my ($self) = @_;

    # Проверим, что хотя бы имя базы и пользователя заданы в конфиге
    for my $param (qw(dbname user)) {
        defined $self->{conf}->{$param} or return error(ECODE_INVALID_PARAM, "empty mandatory config parameter $param");
    }

    my $dsn = "dbi:Pg:dbname=$self->{conf}->{dbname}";
    defined $self->{conf}->{host} and $dsn .= ";host=$self->{conf}->{host}";
    defined $self->{conf}->{port} and $dsn .= ";port=$self->{conf}->{port}";
    $self->{conf}->{password} ||= '';

    $self->{dbh} = DBI->connect($dsn, $self->{conf}->{user}, $self->{conf}->{password}) or return error(ECODE_INTERNAL, "DBI error: $DBI::errstr");
    return E_NO_ERROR;

} # connect_to_db

# маршрутизатор по функциям обработки массивов записей
# либо в message, либо в log
sub insert_data {
    my ($self, $table, $data) = @_;

    $table or return error(ECODE_INVALID_PARAM, "empty table name");
    $data and @$data or return;

    $table eq "message" and return $self->insert_message_data($data);
    $table eq "log" and return $self->insert_log_data($data);

    return error(ECODE_INVALID_PARAM, "unknown table $table");

} # insert_data

# Вставляем записи в таблицу message
# Предварительно вычисляем все id (primary key)
# И удаляем все записи из message с таким id
sub insert_message_data {
    my ($self, $data) = @_;

    $data and @$data or return;

    $self->{dbh}->begin_work();

    # Сначала удалим записи с нашими ID из таблицы (тк они primary key)
    my $err = $self->clear_message_records($data);
    $err and $err ne E_NO_ERROR and do {
        $self->{dbh}->rollback();
        log("insert_message_data: error:", log_hash($err));
        return $err; 
    };

    $self->{dbh}->do(q{copy message(created, id, int_id, str, status) from STDIN (NULL 'null')});
    $self->{dbh}->pg_putcopydata(join("\t", map {$_ || 'null'} @$_{qw(created id int_id str status)})."\n") for @$data;
    $self->{dbh}->pg_putcopyend() or do {
        $self->{dbh}->rollback();
        return error(ECODE_INTERNAL, "SQL error: $DBI::errstr");
    };

    $self->{dbh}->commit();
    return E_NO_ERROR;

} # insert_message_data

sub insert_log_data {
    my ($self, $data) = @_;

    $data and @$data or return;

    $self->{dbh}->begin_work();

    # Чистим записи в таблице log по int_id
    my $err = $self->clear_log_records($data);
    $err and $err ne E_NO_ERROR and do {
        $self->{dbh}->rollback();
        return $err;
    };
    
    # Втыкаем записи в таблицу
    $self->{dbh}->do(q{copy log(created, int_id, str, address) from STDIN (NULL 'null')});
    $self->{dbh}->pg_putcopydata(join("\t", map {$_ || 'null'} @$_{qw(created int_id str address)})."\n") for @$data;
    $self->{dbh}->pg_putcopyend() or do {
        $self->{dbh}->rollback();
        return error(ECODE_INTERNAL, "SQL error: $DBI::errstr");
    };

    $self->{dbh}->commit();

    return E_NO_ERROR;

} # insert_log_data

# Выставляем внутренние временные границы
# Может потом использоваться при чистке данных в таблице log
sub set_stamp_borders {
    my $self = shift;
    $self->{begin_stamp} = shift;
    $self->{end_stamp} = shift;
} # set_stamp_borders

# Если заданы границы временного промежутка, почистим все записи в таблице за этот промежуток по int_id в пачке
sub clear_log_records {
    my ($self, $data) = @_;

    # Если границы не выставлены, чистку по границам не производим
    $self->{begin_stamp} and $self->{end_stamp} or return E_NO_ERROR;
    
    my @ids = map { $_->{int_id} } @$data;
    @ids or return E_NO_ERROR;

    my $res = $self->{dbh}->do(
        q{
            delete from log
            where
            created between $1::timestamp and $2::timestamp and
            int_id = any($3::char(16)[])
        }, undef, 
        $self->{begin_stamp}, $self->{end_stamp}, \@ids,
    );
    defined $res or return error(ECODE_INTERNAL, "SQL error: $DBI::errstr");

    log("clear_log_records: begin $self->{begin_stamp} end $self->{end_stamp} total", scalar @ids, "records, deleted $res");
    return E_NO_ERROR;
};

# Удаляем записи из таблицы message по их id из пачки в $data
sub clear_message_records {
    my ($self, $data) = @_;

    $data and @$data or return E_NO_ERROR;

    my @ids = map { $_->{id} } @$data;
    @ids or return E_NO_ERROR;

    my $res = $self->{dbh}->do(
        q{
            delete from message
            where id = any($1::varchar[])
        }, undef, \@ids,
    );
    defined $res or return error(ECODE_INTERNAL, "SQL error: $DBI::errstr");
    log("clear_message_records: total", scalar @ids, "records, deleted $res");

    return E_NO_ERROR;
} # clear_message_recors

# Сносим содержимое указанной таблицы с момента stamp
# по умолчанию -infinity, то есть все записи
sub clear_table {
    my ($self, $table, $stamp) = @_;

    $stamp ||= '-infinity';
    $table ||= '';
    $table eq 'log' or $table eq 'message' or return error(ECODE_INVALID_PARAM, "only log and message clearing is allowed");

    my $res = $self->{dbh}->do(
        'delete from ' . $table . q{
        where created >= $1::timestamp
        }, undef, $stamp,
    );
    defined $res or return error(ECODE_INTERNAL, "SQL error: $DBI::errstr");
    log("clear_table: $table $stamp: deleted $res records");

    return E_NO_ERROR;
    
} # clear_table

1;
