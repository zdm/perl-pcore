package Pcore::API::SCM::Server::Git;

use Pcore -class;
use Pcore::API::SCM::Upstream;
use Pcore::API::Response;

with qw[Pcore::API::SCM::Server];

sub scm_upstream ( $self, $root ) {
    if ( -f "$root/.git/config" ) {
        my $config = P->file->read_text("$root/.git/config");

        return Pcore::API::SCM::Upstream->new( { uri => $1, clone_is_git => 1 } ) if $config->$* =~ /\s*url\s*=\s*(.+?)$/sm;
    }

    return;
}

sub scm_cmd ( $self, $root, $cb, $cmd ) {
    my $chdir_guard = P->file->chdir($root);

    my @cmd = ( 'git', $cmd->@*, qw[--porcelain -z] );

    P->pm->run_proc(
        \@cmd,
        stdout    => 1,
        stderr    => 1,
        on_finish => sub ($proc) {
            my $api_res;

            if ( $proc->is_success ) {
                $api_res = Pcore::API::Response->new( { status => 200 } );

                $api_res->{result} = [ split /\x00/sm, $proc->stdout ] if $proc->stdout;
            }
            else {
                $api_res = Pcore::API::Response->new( { status => 500, $proc->stderr ? ( reason => ( $proc->stderr =~ /\A(.+?)\n/sm )[0] ) : () } );
            }

            $cb->($api_res);

            return;
        }
    );

    return;
}

sub scm_id ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_init ( $self, $root, $cb, $args = undef ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_clone ( $self, $root, $cb, $args ) {
    my ( $path, $uri, %args ) = $args->@*;

    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_releases ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_latest_release ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_is_commited ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_addremove ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_commit ( $self, $root, $cb, $args ) {
    my $message = $args->[0];

    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_push ( $self, $root, $cb, $args ) {
    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

sub scm_set_tag ( $self, $root, $cb, $args ) {
    my ( $tag, %args ) = $args->@*;

    $tag = [$tag] if !ref $tag;

    ...;    ## no critic qw[ControlStructures::ProhibitYadaOperator]
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::SCM::Server::Git

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
