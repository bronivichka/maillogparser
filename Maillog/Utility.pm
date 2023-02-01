package Maillog::Utility;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw(check_email);

# Проверяем email на валидность
# здесь пока очень простая проверка, для серьезного использования ее надо усовершенствовать
# Если email OK, возвращаем его, иначе undef
sub check_email {
    my ($email) = @_;

    $email or return;

    # Кавычки, пробелы и другое убираем
    $email =~ s/['"`<>\s=:]//g;

    # Проверяем, что вышло
    $email =~ /^[a-z0-9._]+\@[a-z0-9.-]+$/ and return $email;;


    return;

} # email

1;
