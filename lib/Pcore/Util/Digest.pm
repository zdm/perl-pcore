package Pcore::Util::Digest;

use Pcore -export => [qw[md5 md5_hex bcypt bcypt_hex crc32]];
use Digest qw[];    ## no critic qw[Modules::ProhibitEvilModules]

my $BCRYPT_COST_DEFAULT = 10;

sub md5 {
    my $self = shift;
    my @data = @_;

    state $init = do {
        require Digest::MD5;    ## no critic qw[Modules::ProhibitEvilModules]

        1;
    };

    # prepare data for serialization
    for my $item (@data) {
        if ( my $ref = ref $item ) {
            if ( $ref ne 'SCALAR' ) {
                $item = P->data->encode($item)->$*;
            }
            else {
                $item = $item->$*;
            }
        }

        P->text->encode_utf8($item);
    }

    return Digest::MD5::md5(@data);
}

sub md5_hex {
    return unpack 'H*', md5(@_);
}

sub bcrypt ( $self, $password, $salt, $cost = $BCRYPT_COST_DEFAULT ) {
    state $init = do {
        require Digest::Bcrypt;    ## no critic qw[Modules::ProhibitEvilModules]

        1;
    };

    my $bcrypt = Digest::Bcrypt->new;

    $bcrypt->cost($cost);

    $bcrypt->salt($salt);

    $bcrypt->add($password);

    return $bcrypt->digest;
}

sub bcrypt_hex {
    return unpack 'H*', bcrypt(@_);
}

sub crc32 {
    state $init = do {
        require String::CRC32;

        1;
    };

    return String::CRC32::crc32(@_);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 39                   │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
