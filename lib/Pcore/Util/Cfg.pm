package Pcore::Util::Cfg;

use Pcore -const;
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::Data qw[:TYPE encode_data decode_data];

const our $EXT_TYPE_MAP => {
    perl => $DATA_TYPE_PERL,
    json => $DATA_TYPE_JSON,
    cbor => $DATA_TYPE_CBOR,
    yaml => $DATA_TYPE_YAML,
    yml  => $DATA_TYPE_YAML,
    xml  => $DATA_TYPE_XML,
    ini  => $DATA_TYPE_INI,
};

# type - can specify config type, if not defined - type will be get from file extension
# params - params, passed to template
sub read ( $path, %args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $type = delete $args{type};

    use Devel::StackTrace;
    say Devel::StackTrace->new->as_string;
    say '-' x 100;

    die qq[Config file "$path" wasn't found.] if !-f $path;

    $type = $EXT_TYPE_MAP->{$1} if !$type && $path =~ /[.]([^.]+)\z/sm;

    $path = P->file->read_bin($path);

    if ( defined $args{params} ) {
        state $tmpl = P->tmpl;

        $path = $tmpl->( $path, $args{params} );
    }

    $type //= $DATA_TYPE_PERL;

    return decode_data( $type, $path, %args );
}

# type - can specify config type, if not defined - type will be get from file extension
sub write ( $path, $data, %args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    my $type = delete $args{type};

    $type = $EXT_TYPE_MAP->{$1} if !$type && $path =~ /[.]([^.]+)\z/sm;

    $type //= $DATA_TYPE_PERL;

    P->file->write_bin( $path, encode_data( $type, $data, %args ) );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 28, 47               | RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Cfg

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
