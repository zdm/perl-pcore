package Pcore::Util::Digest;

use Pcore -export => [qw[md5 md5_hex bcypt bcypt_hex crc321]];
use Pcore::Util::Text qw[encode_utf8];

my $BCRYPT_COST_DEFAULT = 10;

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

sub crc32 {
    state $init = !!require String::CRC32;

    return &String::CRC32::crc32;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

1;
__END__
=pod

=encoding utf8

=cut
