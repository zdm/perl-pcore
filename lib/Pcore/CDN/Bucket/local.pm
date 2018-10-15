package Pcore::CDN::Bucket::local;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[is_plain_arrayref];

with qw[Pcore::CDN::Bucket];

has lib           => ( init_arg => undef );    # ArrayRef
has default_write => ( init_arg => undef );
has is_local => ( 1, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->{prefix} = '/cdn';

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

            $path = $ENV->{share}->get_storage( $path, 'cdn' );

            next if !$path;
        }

        $cfg{path} = "$path";

        push $self->{lib}->@*, \%cfg;

        $self->{default_write} = $cfg{path} if $cfg{default_write};
    }

    return;
}

# add_header    Cache-Control "public, private, must-revalidate, proxy-revalidate";
sub get_nginx_cfg ($self) {
    my @buf;

    for ( my $i = 0; $i <= $self->{lib}->$#*; $i++ ) {
        my $location = $i == 0 ? '/cdn/' : "\@$self->{lib}->[$i]->{path}";

        my $next = $i < $self->{lib}->$#* ? "\@$self->{lib}->[$i + 1]->{path}" : '=404';

        my $cache_control = $self->{lib}->[$i]->{cache} // 'no-cache';

        push @buf, <<"TXT";
    location $location {
        root          $self->{lib}->[$i]->{path};
        try_files     /../\$uri $next;
        add_header    Cache-Control "$cache_control";
    }
TXT
    }

    return <<"TXT";
@{[join $LF, @buf]}
TXT
}

# TODO check path
# TODO async
# set mode
sub upload ( $self, $path, $data, @args ) {
    die q[Bucket has no default write location] if !$self->{default_write};

    $path = P->path("$self->{default_write}/$path");

    # TODO check, that path is child
    return res 404 if 0;

    P->file->mkpath( $path->dirname, mode => 'rwxr-xr-x' ) || return res [ 500, qq[Can't create CDN path "$path", $!] ] if !-d $path->dirname;

    P->file->write_bin( $path, $data );    # TODO or return res [ 500, qq[Can't write "$path", $!] ];

    return res 200;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 54                   | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
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
