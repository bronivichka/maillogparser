package Maillog::Parser;

use strict;
use warnings;
use Exporter 'import';
use Maillog::Error;
use Maillog::Logger qw(log log_hash);
use Maillog::Utility;
use Data::Dumper;

# Набор функций для обработки записей
# В зависимости от флага
# Заодно может использоваться как определение допустимого значения флага
use constant flags => {
    '<=' => \&add_message_data,
    '=>' => \&add_log_data,
    '->' => \&add_log_data,
    '==' => \&add_log_data,
    '**' => \&add_log_data,
};

# Функция обработки записи по умолчанию
use constant default_data_func => \&add_log_data;

# Строки лога обрабатываются пачками, размер может быть задан в конфиге chunk_size
# Здесь размер пачки по-умолчанию
use constant default_chunk_size => 1000;

sub new {
    my ($class, $params) = @_;

    my $self = {
        conf => $params->{conf} || {}, # конфигурация
        fh => undef, # filehandler для работы с файлом
        fname => undef, # имя читаемого файла
        msg => [], # массив записей для вставки в message, обнуляется в начале парсинга каждой порции (пачки)
        log => [], # массив записей для вставки в log, обнуляется в начале парсинга каждой пачки
        line => 0, # текущий номер строки в файле, сквозной
        count => 0, # количество прочитанных строк в текущей пачке
        begin_stamp => undef, # дата/время первой записи в пачке
        end_stamp => undef, # дата/время последней записи в пачке
        last_stamp => undef, # дата время предыдущей записи, используем при дочитывании пачки по границе секунды
        last_offset => 0, # смещение в файле начала предыдущей строки, используем при дочитывании пачки по границе секунды
    };

    bless ($self, $class);

    return $self;
} # new

# Открываем заданный файл на чтение
sub open {
    my ($self, $file) = @_;

    $file or return error(ECODE_FILE_ERROR, "empty file path");

    open(my $fh, "<", $file) or return error(ECODE_FILE_ERROR, "unable to open file $file: $!"); 
    $self->{fname} = $file;
    $self->{fh} = $fh;

    return E_NO_ERROR;
} # open

# Закрываем файл
# В данном случае ошибка не важна
sub close {
    my ($self) = @_;

    $self->{fh} and close($self->{fh});
} # close

# Парсим файл
# читаем $self->{conf}->{chunk_size} строк и заполняем массивы
# $self->{msg} (строки для таблицы message)
# $self->{log} (строки для таблицы log)
sub parse {
    my ($self) = @_; 

    $self->{conf}->{chunk_size} ||= default_chunk_size;

    my $fh = $self->{fh} or return error(ECODE_INVALID_PARAM, "file is not open");

    # массивы для хранения записей по таблицам
    $self->{msg} = [];
    $self->{log} = [];

    # количество строк в текущей пачке
    $self->{count} = 0;

    # дата/время первой и последней записи в пачке (для удаления записей из log)
    $self->{begin_stamp} = undef;
    $self->{end_stamp} = undef;

    # смещение и дата/время предыдущей записи (для перехода на них при дочитывании строк по границе секунды)
    $self->{last_offset} = $fh->tell();
    $self->{last_stamp} = undef;

    while (<$fh>) {
        chomp;
        $self->{line} ++; 
        $self->{count} ++;

        my $err = $self->parse_line($_);
        # сигнал о том, что пачка кончилась и мы дочитали до границы секунды
        $err eq E_CHUNK and return E_NO_ERROR;
    }

    return E_EOF;

} # parse

# Парсим и обрабатываем одну строку
sub parse_line {
    my ($self, $str) = @_;

    my ($data, $err) = $self->split_line($str);
    $err ne E_NO_ERROR and return $err;

    $self->process_data($data);

} # parse_line

# Разделяем строку на поля (разделитель - пробел)
# Выполняем минимальную проверку на корректность полученных данных в массиве (минимальное кол-во полей - 4)
# Заполняем хэш $data значениями
# created - дата/время записи в логе
# id - идентификатор в строке с флагом <= (id=XXX)
# int_id - внутренний идентификатор почтового сервера из лога
# str - строка без времени и даты
# flag - флаг из "дозволенных" <= => -> ** ==
# address - адрес получателя
# routed_address - в строках с :blackhole: адрес получателя (небольшая спец обработка)
sub split_line {
    my ($self, $str) = @_;

    # разделитель полей - пробел
    my @fields = split(" ", $str);

    # проверим на всякий случай, что минимальное количество полей присутствует (включая флаг)
    @fields >= 4 or return {}, $self->skip_data({}, "incorrect line $str");

    # дата/время текущей записи
    my $stamp = join(" ", @fields[0,1]);

    # int_id проверяем сразу его длину
    my $int_id = $fields[2];
    length($int_id) == 16 or return {}, $self->skip_data({}, "incorrect int_id $str");

    # Прочитали запись, но еще не обработали
    # Самое время проверить, не в режиме ли мы дочитывания строк до конца секунды
    # Если так, проверяем, изменилось ли время и если да - не обрабатываем данные, откатываемся на начало строки и выходим
    $self->{count} > $self->{conf}->{chunk_size} and 
    $self->{last_stamp} ne $stamp and do {
        $self->{fh}->seek($self->{last_offset}, 0);
        return undef, E_CHUNK;
    };

    # выставляем параметры last_*
    $self->{last_offset} = $self->{fh}->tell();
    $self->{last_stamp} = $stamp;

    # основные параметры строки: дата/время, id, строка без временной метки и тд
    my $data = {
        created => $stamp,
        id => undef,
        int_id => $int_id,
        str => join(" ", @fields[2..$#fields]),
        flag => exists flags->{$fields[3]} ? $fields[3] : 'default',
        address => $fields[4],
        routed_address => $fields[5],
    };

    # Если это первая запись в пачке, запишем ее дату/время в begin_stamp
    # Это нужно, чтобы перед записью данных в log удалить записи с таким int_id с момента begin_stamp по end_stamp
    $self->{begin_stamp} ||= $data->{created};

    # А сюда всегда записываем дату/время последней записи
    $self->{end_stamp} = $data->{created};

    return $data, E_NO_ERROR;

} # split_line

# Обрабатываем данные в зависимости от флага
sub process_data {
    my ($self, $data) = @_;

    $data and $data->{flag} or return $self->skip_data($data, "incorrect data");

    # По флагу определяем функцию окончательной обработки
    # Если не нашли, выбираем функцию по умолчанию
    my $func = flags->{$data->{flag}};
    $func ||= default_data_func;

    # Вызываем функцию обработки записи
    return &{$func}($self, $data);

} # process_data

# Обрабатываем данные из строки прибытия сообщения (флаг <=)
# Кладем в массив $self->{msg}
sub add_message_data {
    my ($self, $data) = @_;

    $data and %$data and $data->{str} or return $self->skip_data($data, "empty data");

    # Это сообщения от локального почтового пользователя mailnull (отпины по поводу того, что не удалось кому-то доставить сообщение, скорее всего)
    # Они не имеют паттерна id=(.*)
    # 2012-02-13 15:10:15 1RwtnT-000B7I-0D <= <> R=1RwtmW-000MsX-E0 U=mailnull P=local S=2917
    # Теоретически это можно связать с исходным сообщением по R=1RwtmW-000MsX-E0
    # Но здесь мы этого не делаем, пропускаем такую строку
    $data->{str} =~ /id=(.*)$/ or return $self->skip_data($data, "no id pattern");
    $data->{id} = $1;

    push @{$self->{msg}}, $data;

    return E_NO_ERROR;
} # add_message_data

sub add_log_data {
    my ($self, $data) = @_;

    $data and %$data or return $self->skip_data($data, "empty data");

    # Если задан адрес, проверим, не является ли он чем-то наподобие :blackhole:
    # Это, видимо, отправка сообщения в /dev/null
    # В такой записи адрес получателя находится в $data->{routed_address}
    #
    # 2012-02-13 14:39:22 1RwtJa-000AFB-07 => :blackhole: <tpxmuwr@somehost.ru> R=blackhole_router
    #
    $data->{address} and do {
        $data->{address} =~ /^:[^:]+:$/ and do {
            $data->{routed_address} =~ s/[<>]//g;
            $data->{address} = $data->{routed_address};
        };

        # финально проверяем, что address похож на email
        $data->{address} = check_email($data->{address});
    };


    push @{$self->{log}}, $data;

    return E_NO_ERROR;
} # add_log_data

# Пропускаем запись
# Не добавляем ни в какой массив результатов
# Можно использовать для того, чтобы логгировать такое событие
sub skip_data {
    my ($self, $data, $text) = @_;

    $text ||= '';
    log("skip_data: line $self->{line} skipped data", $text, log_hash($data));
    return E_SKIPPED;

} # skip_data

1;
