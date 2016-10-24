package Pcore::App::API::Backend::Local::sqlite::AppRole;

use Pcore -role, -promise, -status;

sub get_app_role ( $self, $role_id, $cb ) {

    # role_id is role id
    if ( $role_id =~ /\A\d+\z/sm ) {
        if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE id = ?], [$role_id] ) ) {
            $cb->( status 200, role => $role );
        }
        else {
            $cb->( status [ 404, qq[App role "$role_id" not found] ] );
        }
    }

    # role id is app_id/role_name
    else {
        my ( $app_id, $role_name ) = split m[/]sm, $role_id;

        # $app_id is app id
        if ( $app_id =~ /\A\d+\z/sm ) {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE app_id = ? AND name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, role => $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }

        # $app_id is app name
        else {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app, api_app_role WHERE api_app.name = ? AND api_app.id = api_app_role.app_id AND api_app_role.name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, role => $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }
    }

    return;
}

sub set_app_role_enabled ( $self, $role_id, $enabled, $cb ) {
    $self->get_app_role(
        $role_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $role = $res->{role};

            if ( ( $enabled && !$role->{enabled} ) || ( !$enabled && $role->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_app_role SET enabled = ? WHERE id = ?], [ !!$enabled, $role->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app role enabled' ] );
                }
            }
            else {

                # not modified
                $cb->( status 304 );
            }

            return;
        }
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::AppRole

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
