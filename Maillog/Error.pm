package Maillog::Error;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw(
    ECODE_FILE_ERROR ECODE_INVALID_PARAM 
    ECODE_INTERNAL
    E_NO_ERROR E_EOF E_CHUNK E_SKIPPED
    error
);

use constant {
    ECODE_FILE_ERROR => 100,
    ECODE_INVALID_PARAM => 101,
    ECODE_EOF => 102,
    ECODE_INTERNAL => 103,
    ECODE_CHUNK => 104,
    ECODE_SKIPPED => 105,
};

use constant E_NO_ERROR => {code => 0, message => undef};
use constant E_EOF => {code => ECODE_EOF, message => undef};
use constant E_CHUNK => {code => ECODE_CHUNK, message => undef};
use constant E_SKIPPED => {code => ECODE_SKIPPED, message => undef};

# Составляем ошибку из кода и сообщения
sub error {
    my ($code, $message) = @_; 

    return {
        code => $code,
        message => $message,
    };  
} # error

1;
