package Maillog::Api;

use strict;
use warnings;

use Maillog::Database;
use Maillog::Error;
use Maillog::Logger qw(log log_hash);
use Maillog::Utility;

use HTTP::Daemon;
use HTTP::Status;
use HTTP::Response;
use HTTP::Headers;
use CGI qw();

# Параметры сервера по умолчанию
use constant default => {
    host => 'localhost',
    port => 80,
    search_limit => 50
};

sub new {
    my ($class, $params) = @_;

    my $self = {
        dbh => undef, # Database handler
        conf => $params->{conf} || {}, # config parameters
    };
    bless ($self, $class);

    for my $key (keys default) {
        defined $self->{conf}->{$key} or $self->{conf}->{$key} = default->{$key};
    }

    # Database object
    my $err;
    ($self->{dbh}, $err) = Maillog::Database->new($params->{db_conf});
    $err and $err ne E_NO_ERROR and return undef, $err;

    return $self;

} # new

sub run {
    my ($self) = @_;

    my $daemon = HTTP::Daemon->new(
        LocalAddr => $self->{conf}->{host},
        LocalPort => $self->{conf}->{port},
    ) or do {
        log("run: unable to start HTTP server on host $self->{conf}->{host} and port $self->{conf}->{port}: $!");
        return error(ECODE_INTERNAL, "unable to start: $!");
    };  

    log("HTTP daemon started on", $daemon->url);

    while (my $client = $daemon->accept) {
        while (my $request = $client->get_request) {
            if ($request->method eq 'POST' and $request->uri->path =~ /^\/search\/?/) {
                $self->process_client($request, $client);
                next;
            }
            # Никакие другие методы и урлы не принимаем
            $client->send_error(RC_FORBIDDEN);
            $client->close;
        }
    }   

    log("HTTP daemon Finished");
    return E_NO_ERROR;

} # run

# Обработка запроса клиента
sub process_client {
    my ($self, $request, $client) = @_;

    # Декодируем форму, получим значение полей в хэш
    my $decoded = CGI->new($request->decoded_content)->Vars;

    # Получим, наконец, email, попутно проверив его валидность
    my $email = $self->get_content_email($decoded);

    # Запросим историю
    my $data = $self->{dbh}->address_history($email, $self->{conf}->{search_limit});

    # Проверим размер массива - если он больше запрошенного лимита, добавим сообщение об этом
    my $message = '';
    @$data > $self->{conf}->{search_limit} and do {
        @$data = @$data[0..$self->{conf}->{search_limit} - 1];
        $message = "<p>Найдено больше $self->{conf}->{search_limit} записей</p>";
    };
    $message .= '<p>';
    for (@$data) {
        $message .= join(" ", @$_) . "<br/>";
    }
    $message .= '</p>';

    my $headers = HTTP::Headers->new();
    $headers->header(
        'Content-Length' => length($message),
        'Accept' => '*/*',
        'Content-Type' => 'text/html',
        'Access-Control-Allow-Origin' => '*',
    );

    # Ответим клиенту
    my $response = HTTP::Response->new(RC_OK, undef, $headers, $message);

    $client->send_response($response);
    $client->close;
} # process_client

# Вытаскиваем параметр address из формы
# заодно проверяем сам email на корректность
# проверка здесь достатовно простая
sub get_content_email {
    my ($self, $data) = @_;

    $data and %$data or return;
    return check_email($data->{address});
    
} # get_content_email

1;
