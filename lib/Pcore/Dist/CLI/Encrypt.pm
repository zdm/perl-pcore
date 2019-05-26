package Pcore::Dist::CLI::Encrypt;

use Pcore -class, -ansi;

extends qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'encrypt distribution',
        opt      => { force => { desc => 'perform encryption', }, },
        arg      => [
            path => {
                desc => 'path to the root directory to encrypt perl files recursively',
                isa  => 'Path',
                min  => 0,
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    return if !$opt->{force};

    my $root = $arg->{path} ? P->path( $arg->{path} ) : $self->get_dist->{root};

    for my $path ( $root->read_dir( max_depth => 0, is_dir => 0 )->@* ) {

        # encrypt
        if ( $path->mime_has_tag( 'perl', 1 ) && !$path->mime_has_tag( 'perl-cpanfile', 1 ) ) {
            my $res = P->src->compress(
                path   => "$root/$path",
                filter => {
                    perl_compress_keep_ln => 1,
                    perl_strip_comment    => 1,
                    perl_strip_pod        => 1,
                    perl_encrypt          => 1,
                }
            );

            die qq[Can't encrypt "$root/$path", $res] if !$res;
        }
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Encrypt - encrypt distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
