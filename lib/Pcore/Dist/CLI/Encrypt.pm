package Pcore::Dist::CLI::Encrypt;

use Pcore -class, -ansi;

extends qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'encrypt distribution',
        opt      => { force => { desc => 'perform encryption', }, },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    return if !$opt->{force};

    my $dist = $self->get_dist;

    for my $path ( $dist->{root}->read_dir( max_depth => 0, is_dir => 0 )->@* ) {

        # encrypt
        if ( $path->mime_has_tag( 'perl', 1 ) && !$path->mime_has_tag( 'perl-cpanfile', 1 ) ) {
            my $res = P->src->compress(
                path   => "$dist->{root}/$path",
                filter => {
                    perl_compress_keep_ln => 1,
                    perl_strip_comment    => 1,
                    perl_strip_pod        => 1,
                    perl_encrypt          => 1,
                }
            );

            die qq[Can't encrypt "$dist->{root}/$path", $res] if !$res;
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
