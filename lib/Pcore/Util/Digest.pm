package Pcore::Util::Digest;

use Pcore -export => {
    CRC       => [qw[crc32]],
    MD5       => [qw[md5 md5_hex]],
    SHA1      => [qw[sha1 sha1_hex]],
    HMAC_SHA1 => [qw[hmac_sha1 hmac_sha1_hex]],
    SHA3      => [qw[sha3_224 sha3_224_hex sha3_256 sha3_256_hex sha3_384 sha3_384_hex sha3_512 sha3_512_hex]],
};
use Pcore::Util::Text qw[encode_utf8];
use Digest::SHA1 qw[sha1 sha1_hex];
use Digest::SHA qw[hmac_sha1 hmac_sha1_hex];
use Digest::SHA3 qw[sha3_224 sha3_224_hex sha3_256 sha3_256_hex sha3_384 sha3_384_hex sha3_512 sha3_512_hex];

my $BCRYPT_COST_DEFAULT = 10;

sub crc32 {
    state $init = !!require String::CRC32;

    return &String::CRC32::crc32;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub md5 {
    my @data = @_;

    state $init = !!require Digest::MD5;

    # prepare data for serialization
    for my $item (@data) {
        if ( my $ref = ref $item ) {
            if ( $ref ne 'SCALAR' ) {
                $item = P->data->to_json($item)->$*;
            }
            else {
                $item = $item->$*;
            }
        }

        encode_utf8 $item;
    }

    return Digest::MD5::md5(@data);
}

sub md5_hex {
    return unpack 'H*', &md5;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

1;
__END__
=pod

=encoding utf8

=cut
