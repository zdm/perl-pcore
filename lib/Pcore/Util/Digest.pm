package Pcore::Util::Digest;

use Pcore -export => [qw[crc32 md5 md5_hex sha1 sha1_hex hmac_sha1 hmac_sha1_hex]];
use Pcore::Util::Text qw[encode_utf8];
use Digest::SHA1 qw[sha1 sha1_hex];
use Digest::SHA qw[hmac_sha1 hmac_sha1_hex];

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
