package Pcore::Src1;

use Pcore -class, -const, -res, -export, -ansi;
use Pcore::Util::Scalar qw[is_path is_plain_arrayref is_plain_hashref];
use Pcore::Util::Text qw[encode_utf8 decode_eol lcut_all rcut_all rtrim_multi remove_bom];
use Pcore::Util::Digest qw[md5_hex];

has path    => ();    # Scalar, ArrayRef
has data    => ();
has type    => ();    # ArrayRef[ Enum ['css', 'html', 'js', 'json', 'perl']], list of types to process, used if path is directory
has ignore  => 1;     # Bool, ignore unsupported file types
has filter  => ();    # HashRef, additional filter arguments
has dry_run => ();    # Bool, if true - do not write results to the source path
has report  => ();    # print report

const our $SRC_DECOMPRESS => 1;
const our $SRC_COMPRESS   => 2;
const our $SRC_OBFUSCATE  => 3;

const our $STATUS_REASON => {
    200 => 'OK',
    201 => 'Warning',
    202 => 'File skipped',
    404 => 'File not found',
    500 => 'Error',
};

const our $STATUS_COLOR => {
    200 => $BOLD . $GREEN,
    201 => $YELLOW,
    404 => $BOLD . $RED,
    500 => $BOLD . $RED,
};

# TODO do we need this???
our $EXPORT = { ACTION => [qw[$SRC_DECOMPRESS $SRC_COMPRESS $SRC_OBFUSCATE]] };

# TODO CLI mode

sub cfg ($self) {
    state $cfg = $ENV->{share}->read_cfg( 'Pcore', 'data', 'src.yaml' );

    return $cfg;
}

sub run ( $self, $action ) {

    # convert type to HashRef
    if ( defined $self->{type} && !is_plain_hashref $self->{type} ) {
        if ( is_plain_arrayref $self->{type} ) {
            $self->{type} = { map { $_ => undef } $self->{type}->@* };
        }
        else {
            $self->{type} = { $self->{type} => undef };
        }
    }

    my $res;

    # file content is provided
    if ( defined $self->{data} ) {
        $res = $self->_process_file( $action, $self->{path}, $self->{data} );
    }

    # file content is not provided
    else {
        $res = $self->_process_files( $action, $self->{path} );
    }

    return $res;
}

# TODO find path prefix
sub _process_files ( $self, $action, $paths ) {
    my $total = res 200;

    my %path;

    # build absolute paths list
    for my $path ( is_plain_arrayref $paths ? $paths->@* : $paths ) {
        next if !defined $path;

        $path = P->path($path) if !is_path $path;

        $path->to_abs;

        if ( -d $path ) {
            for ( ( $path->read_dir( abs => 1, max_depth => 0, is_dir => 0 ) // [] )->@* ) { $path{$_} = $_ }
        }
        else {
            $path{$path} = $path;
        }
    }

    my ( $max_path_len, $prefix, $use_prefix );

    # find longest common prefix
    if ( $self->{report} ) {
        for my $path ( values %path ) {
            my $dirname = "$path->{dirname}/";

            if ( !defined $prefix ) {
                $prefix = $dirname;

                $max_path_len = length $path;
            }
            else {
                $max_path_len = length $path if length $path > $max_path_len;

                if ( "$prefix\x00$dirname" =~ /^(.*).*\x00\1.*$/sm ) {
                    $prefix = $1;

                    $use_prefix = 1;
                }
            }
        }

        # find max. path length
        $max_path_len -= length $prefix if $use_prefix;
    }

    my $tbl;

    for my $key ( sort keys %path ) {
        my $res = $self->_process_file( $action, $path{$key} );

        if ( $res != 202 ) {
            if ( $res->{status} > $total->{status} ) {
                $total->{status} = $res->{status};
                $total->{reason} = $STATUS_REASON->{ $total->{status} };
            }

            $total->{ $res->{status} }++;
            $total->{modified}++ if $res->{is_modified};

            $self->_report_file( \$tbl, $use_prefix ? substr $key, length $prefix : $key, $res, $max_path_len ) if $self->{report};
        }
    }

    print $tbl->finish if defined $tbl;

    $self->_report_total($total) if $self->{report};

    return $total;
}

sub _process_file ( $self, $action, $path = undef, $data = undef ) {
    my $res = res [ 200, $STATUS_REASON ],
      is_modified => 0,
      in_size     => 0,
      out_size    => 0,
      size_delta  => 0;

    $path = P->path($path) if !is_path $path;

    # detect file type
    my $filter_profile;
    my $cfg = $self->cfg;
    my $path_mime_tags = $path->mime_tags( defined $data ? \$data : 1 );

    for ( keys $cfg->{mime_tag}->%* ) { $filter_profile = $cfg->{mime_tag}->{$_} and last if exists $path_mime_tags->{$_} }

    # file type is known
    if ( defined $filter_profile ) {

        # file is filtered by the type filter and in ignore mode
        if ( defined $self->{type} && !exists $self->{type}->{ $filter_profile->{type} } && $self->{ignore} ) {
            $res->{status} = 202;
            $res->{reason} = $STATUS_REASON->{202};
            return $res;
        }
    }

    # filte type is unknown and in ignore mode
    elsif ( $self->{ignore} ) {
        $res->{status} = 202;
        $res->{reason} = $STATUS_REASON->{202};
        return $res;
    }

    my $write_data;

    # read file
    if ( !defined $data ) {
        if ( defined $path && -f $path ) {
            $data = P->file->read_bin( $path->encoded )->$*;

            $write_data = 1;
        }

        # file not found
        else {
            $res->{status} = 404;
            $res->{reason} = $STATUS_REASON->{404};
            return $res;
        }
    }
    else {
        encode_utf8 $data;
    }

    $res->{in_size} = bytes::length $data;
    my $in_md5 = md5_hex $data;

    # run filter
    if ($filter_profile) {
        my $filter_args->@{ keys $filter_profile->%* } = values $filter_profile->%*;

        my $filter_type = delete $filter_args->{type};

        $filter_args->@{ keys $self->{filter}->%* } = values $self->{filter}->%* if defined $self->{filter};

        my $filter_res = P->class->load( $filter_type, ns => 'Pcore::Src1' )->new(
            $filter_args->%*,
            file => $self,
            data => \$data,
        )->run($action);

        $res->{status} = $filter_res->{status};
        $res->{reason} = $filter_res->{reason};
    }

    # trim
    if ( $action == $SRC_DECOMPRESS ) {
        decode_eol $data;    # decode CRLF to internal \n representation

        lcut_all $data;      # trim leading horizontal whitespaces

        rcut_all $data;      # trim trailing horizontal whitespaces

        rtrim_multi $data;   # right trim each line

        $data =~ s/\t/    /smg;    # convert tabs to spaces

        $data .= $LF;
    }

    my $out_md5 = md5_hex $data;
    $res->{is_modified} = $in_md5 ne $out_md5;
    $res->{out_size}    = bytes::length $data;
    $res->{size_delta}  = $res->{out_size} - $res->{in_size};

    # write file
    if ($write_data) {
        if ( $res->{is_modified} && !$self->{dry_run} ) { P->file->write_bin( $path->encoded, $data ) }
    }
    else {
        $res->{data} = $data;
    }

    return $res;
}

sub _report_file ( $self, $tbl, $path, $res, $max_path_len ) {
    if ( !defined $tbl->$* ) {
        $tbl->$* = P->text->table(    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
            style    => 'compact',
            top_line => 1,
            cols     => [
                path => {
                    width => $max_path_len + 2,
                    align => -1,
                },
                severity => {
                    width => 25,
                    align => 1,
                },
                size => {
                    width => 10,
                    align => 1,
                },
                size_delta => {
                    title => 'SIZE DELTA',
                    width => 16,
                    align => 1,
                },
                modified => {
                    width => 12,
                    align => 1,
                },
            ],
        );

        print $tbl->$*->render_header;
    }

    my @row;

    # path
    push @row, $path;

    # severity
    push @row, $STATUS_COLOR->{ $res->{status} } . uc( $res->{reason} ) . $RESET;

    # size
    push @row, $res->{out_size};

    # size delta
    if ( !$res->{size_delta} ) {
        push @row, ' - ';
    }
    elsif ( $res->{size_delta} > 0 ) {
        push @row, $BOLD . $RED . "+$res->{size_delta} bytes" . $RESET;
    }
    else {
        push @row, $BOLD . $GREEN . "$res->{size_delta} bytes" . $RESET;
    }

    # modified
    push @row, ( $res->{is_modified} ? $BOLD . $WHITE . $ON_RED . ' modified ' . $RESET : ' - ' );

    print $tbl->$*->render_row( \@row );

    return;
}

sub _report_total ( $self, $total ) {
    return if !defined $total;

    my $tbl = P->text->table(
        style => 'full',
        cols  => [
            type => {
                width => 16,
                align => 1,
            },
            count => {
                width => 10,
                align => -1,
            },
        ],
    );

    print $tbl->render_header;

    for my $status ( 200, 201, 500, 404 ) {
        print $tbl->render_row( [ $STATUS_COLOR->{$status} . uc( $STATUS_REASON->{$status} ) . $RESET, $STATUS_COLOR->{$status} . ( $total->{$status} // 0 ) . $RESET ] );
    }

    print $tbl->render_row( [ 'MODIFIED', $total->{modified} // 0 ] );

    print $tbl->finish;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 74                   | * Subroutine "_process_files" with high complexity score (23)                                                  |
## |      | 147                  | * Subroutine "_process_file" with high complexity score (23)                                                   |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 254                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 110                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 213                  | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
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
