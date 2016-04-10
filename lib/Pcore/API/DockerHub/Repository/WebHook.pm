package Pcore::API::DockerHub::Repository::WebHook;

use Pcore -class;
use Pcore::API::DockerHub::Repository::WebHook::Hook;

extends qw[Pcore::API::Response];

has repo => ( is => 'ro', isa => InstanceOf ['Pcore::API::DockerHub::Repository'], required => 1 );
has id => ( is => 'lazy', isa => Int, required => 1 );

sub remove ( $self, % ) {
    my %args = (
        cb => undef,
        splice @_, 1
    );

    return $self->repo->api->_request( 'delete', "/repositories/$self->{repo}->{owner}/$self->{repo}->{name}/webhooks/$self->{id}/", 1, undef, $args{cb} );
}

sub create_hook ( $self, $url, % ) {
    my %args = (
        cb => undef,
        splice @_, 3
    );

    return $self->repo->api->_request( 'post', "/repositories/$self->{repo}->{owner}/$self->{repo}->{name}/webhooks/$self->{id}/hooks/", 1, { hook_url => $url }, $args{cb} );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 17, 26               │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 12, 21               │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::DockerHub::Repository::WebHook

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
