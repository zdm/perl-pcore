package Pcore::CDN::Bucket::local;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[is_plain_arrayref];

with qw[Pcore::CDN::Bucket];

has lib           => ( init_arg => undef );    # ArrayRef
has default_write => ( init_arg => undef );
has is_local => ( 1, init_arg => undef );

# TODO "www"
sub BUILD ( $self, $args ) {
    $self->{prefix} = '';

    # load libs
    for my $lib ( $args->{lib}->@* ) {
        my ( $path, %cfg );

        if ( is_plain_arrayref $lib) {
            ( $path, %cfg ) = $lib->@*;
        }
        else {
            $path = $lib;
        }

        # $path is absolute
        if ( $path =~ m[\A/]sm ) {
            P->file->mkpath( $path, mode => 'rwxr-xr-x' ) || die qq[Can't create CDN path "$path", $!] if !-d $path;
        }

        # $path is dist name
        else {
            P->class->load( $path =~ s/-/::/smgr );

            $path = $ENV->{share}->get_storage( $path, 'www' );

            next if !$path;
        }

        $cfg{path} = "$path";

        push $self->{lib}->@*, \%cfg;

        $self->{default_write} = $cfg{path} if $cfg{default_write};
    }

    return;
}

# TODO maybe create local temp bucket automatically
# P->file->mkpath( "$ENV->{DATA_DIR}share", mode => 'rwxr-xr-x' ) if !-e "$ENV->{DATA_DIR}share/";
# $ENV->{share}->register_lib( 'autostars', "$ENV->{DATA_DIR}share/" );
sub get_nginx_cfg ($self) {
    my @buf;

    my $locations;

    for my $lib ( $self->{lib}->@* ) {
        my $storage = $ENV->{share}->get_storage( $lib, 'www' );

        next if !$storage || !-d "$storage/static";

        push $locations->@*, $storage;
    }

    # add_header    Cache-Control "public, private, must-revalidate, proxy-revalidate";

    for ( my $i = 0; $i <= $locations->$#*; $i++ ) {
        my $location = $i == 0 ? '/static/' : "\@$locations->[$i]";

        my $next = $i < $locations->$#* ? "\@$locations->[$i + 1]" : '=404';

        push @buf, <<"TXT";
    location $location {
        add_header    Cache-Control "public, max-age=30672000";
        root          $locations->[$i];
        try_files     \$uri $next;
    }
TXT
    }

    return <<"TXT";
@{[join $LF, @buf]}
TXT
}

# TODO async
sub write ( $self, $path, $data, @args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Bucket has no default write location] if !$self->{default_write};

    $path = P->path("$self->{default_write}/$path");

    # TODO check, that path is child
    return res 404 if 0;

    P->file->mkpath( $path->dirname, mode => 'rwxr-xr-x' ) || return res [ 500, qq[Can't create CDN path "$path", $!] ] if !-d $path->dirname;

    P->file->write_bin( $path, $data );       # TODO or return res [ 500, qq[Can't write "$path", $!] ];

    return res 200;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 14                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 69                   | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket::local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
