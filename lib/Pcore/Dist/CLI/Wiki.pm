package Pcore::Dist::CLI::Wiki;

use Pcore -class;
use Pcore::API::SCM::Const qw[:ALL];

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return { abstract => 'generate wiki pages', };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    if ( !-d $dist->root . 'wiki/' ) {
        my $confirm = P->term->prompt( qq[Wiki wasn't found. Clone upstream wiki?], [qw[yes no]], enter => 1 );

        exit 3 if $confirm eq 'no';

        exit 3 if !$self->_clone_upstream_wiki($dist);
    }

    $dist->build->wiki->run;

    return;
}

sub _clone_upstream_wiki ( $self, $dist ) {
    if ( !$dist->scm ) {
        say q[SCM wasn't found];

        return;
    }
    elsif ( !$dist->scm->upstream || !$dist->scm->upstream->hosting_api_class ) {
        say q[Invalid SCM upstream];

        return;
    }

    my $upstream = $dist->scm->upstream;

    my $upstream_api = $upstream->hosting_api;

    my $clone_uri;

    if ( $upstream->local_scm_type == $SCM_TYPE_HG ) {
        if   ( $upstream->remote_scm_type == $SCM_TYPE_HG ) { $clone_uri = $upstream_api->clone_uri_wiki_ssh }
        else                                                { $clone_uri = $upstream_api->clone_uri_wiki_ssh_hggit }
    }
    else {
        $clone_uri = $upstream_api->clone_uri_wiki_ssh;
    }

    print qq[Cloning upstream wiki "$clone_uri" ... ];

    if ( my $res = Pcore::API::SCM->scm_clone( $dist->root . '/wiki/', $clone_uri, update => 'tip' ) ) {
        say 'done';

        return 1;
    }
    else {
        say $res->reason;

        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 16                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Wiki - generate wiki pages

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
