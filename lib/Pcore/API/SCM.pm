package Pcore::API::SCM;

use Pcore -const, -class, -export => { CONST => [qw[$SCM_TYPE_MERCURIAL $SCM_TYPE_GIT]] };

const our $SCM_TYPE_MERCURIAL => 1;
const our $SCM_TYPE_GIT       => 2;

has path => ( is => 'ro', isa => Str, required => 1 );
has type => ( is => 'ro', isa => Maybe [ Enum [ $SCM_TYPE_MERCURIAL, $SCM_TYPE_GIT ] ], init_arg => undef );

has server => ( is => 'lazy', isa => ConsumerOf ['Pcore::API::SCM::Server'], init_arg => undef );

around new => sub ( $orig, $self, $path ) {
    return $self->$orig( { path => P->path( $path, is_dir => 1 )->realpath->to_string } );
};

sub _build_server ($self) {
    if ( $self->type == $SCM_TYPE_MERCURIAL ) {
        require Pcore::API::SCM::Server::Mercurial;

        return Pcore::API::SCM::Server::Mercurial->new;
    }
    elsif ( $self->type == $SCM_TYPE_GIT ) {
        require Pcore::API::SCM::Server::Git;

        return Pcore::API::SCM::Server::Git->new;
    }

    return;
}

sub scm_cmd ( $self, @cmd ) {
    return $self->_request( 'scm_cmd', [@cmd] );
}

sub scm_id ( $self, $cb = undef ) {
    return $self->_request( 'scm_id', [$cb] );
}

sub scm_init ( $self, $cb = undef ) {
    return $self->_request( 'scm_init', [$cb] );
}

# TODO clone to temp dir, move
sub scm_clone ( $self, $url, @ ) {
    return $self->_request( 'scm_clone', [ splice @_, 1 ] );
}

sub scm_releases ( $self, $cb = undef ) {
    return $self->_request( 'scm_releases', [$cb] );
}

sub scm_latest_tag ( $self, $cb = undef ) {
    return $self->_request( 'scm_latest_tag', [$cb] );
}

sub scm_is_commited ( $self, $cb = undef ) {
    return $self->_request( 'scm_is_commited', [$cb] );
}

sub scm_addremove ( $self, $cb = undef ) {
    return $self->_request( 'scm_addremove', [$cb] );
}

sub scm_commit ( $self, $message, $cb = undef ) {
    return $self->_request( 'scm_commit', [$cb] );
}

sub scm_push ( $self, $cb = undef ) {
    return $self->_request( 'scm_push', [$cb] );
}

sub scm_set_tag ( $self, $tag, @ ) {
    return $self->_request( 'scm_set_tag', [ splice @_, 1 ] );
}

sub scm_branch ( $self, $cb = undef ) {
    return $self->_request( 'scm_branch', [$cb] );
}

sub _request ( $self, $method, $args ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $cb = ref $args->[-1] eq 'CODE' ? pop $args->@* : undef;

    $self->server->$method(
        $self->path,
        sub ($res) {
            $cb->($res) if $cb;

            $blocking_cv->($res) if $blocking_cv;

            return;
        },
        $args
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::SCM

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
