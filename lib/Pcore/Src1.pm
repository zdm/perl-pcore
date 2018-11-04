package Pcore::Src1;

use Pcore -class, -const, -res, -export;
use Pcore::Util::Scalar qw[is_path];
use Pcore::Util::Text qw[encode_utf8 decode_eol lcut_all rcut_all rtrim_multi remove_bom];

has path       => ();
has data       => ();
has force_trim => ();    # Bool, trim file, event if file type is not supported, used for vim integration
has filter     => ();    # HashRef, additionals filters
has dry_run    => ();    # Bool, if true - do not write results to the source path

const our $SRC_DECOMPRESS => 1;
const our $SRC_COMPRESS   => 2;
const our $SRC_OBFUSCATE  => 3;

our $EXPORT = { ACTION => [qw[$SRC_DECOMPRESS $SRC_COMPRESS $SRC_OBFUSCATE]] };

sub cfg ($self) {
    state $cfg = $ENV->{share}->read_cfg( 'Pcore', 'data', 'src.yaml' );

    return $cfg;
}

sub run ( $self, $action ) {
    my $res = res 200,
      in_size     => 0,
      in_md5      => 0,
      out_size    => 0,
      out_md5     => 0,
      was_changed => 0,
      size_diff   => 0;

    my $path = $self->{path};

    $self->{path} = $path = P->path($path) if defined $path && !is_path $path;

    my $data = $self->{data};
    my $read;

    # read file
    if ( !defined $data ) {
        if ( defined $path && -f $path ) {
            $data = P->file->read_bin( $path->encoded )->$*;

            $read = 1;
        }

        # file not found
        else {
            $res->{status} = 404;
            $res->{reason} = 'File not found';

            return res;
        }
    }

    $res->{in_size} = bytes::length $data;
    $res->{in_md5}  = P->digest->md5_hex($data);

    # detect file type
    my $filter_profile;
    my $cfg            = $self->cfg;
    my $path_mime_tags = $path->mime_tags( \$data );

    for ( keys $cfg->{mime_tag}->%* ) { $filter_profile = $cfg->{mime_tag}->{$_} and last if exists $path_mime_tags->{$_} }

    # detect filetype, require and run filter
    if ($filter_profile) {
        my $filter_args->@{ keys $filter_profile->%* } = values $filter_profile->%*;

        my $filter_type = delete $filter_args->{type};

        $filter_args->@{ keys $self->{filter_args}->%* } = values $self->{filter_args}->%* if defined $self->{filter_args};

        my $filter_res = P->class->load( $filter_type, ns => 'Pcore::Src1' )->new(
            $filter_args->%*,
            file => $self,
            data => \$data,
        )->run($action);

        $res->{status} = $filter_res->{status};
        $res->{reason} = $filter_res->{reason};
    }

    # trim
    if ( $action == $SRC_DECOMPRESS && ( $filter_profile || $self->{force_trim} ) ) {
        decode_eol $data;    # decode CRLF to internal \n representation

        lcut_all $data;      # trim leading horizontal whitespaces

        rcut_all $data;      # trim trailing horizontal whitespaces

        rtrim_multi $data;   # right trim each line

        $data =~ s/\t/    /smg;    # convert tabs to spaces

        $data .= $LF;
    }

    $res->{out_size}    = bytes::length $data;
    $res->{out_md5}     = P->digest->md5_hex($data);
    $res->{was_changed} = $res->{in_md5} ne $res->{out_md5};
    $res->{size_diff}   = $res->{out_size} - $res->{in_size};

    # write file
    if ($read) {
        if ( $res->{was_changed} && !$self->{dry_run} ) { P->file->write_bin( $path->encoded, $data ) }
    }
    else {
        $res->{data} = $data;
    }

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 76                   | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
