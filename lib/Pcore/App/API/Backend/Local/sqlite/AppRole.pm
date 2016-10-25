package Pcore::App::API::Backend::Local::sqlite::AppRole;

use Pcore -role, -promise, -status;

sub get_app_role ( $self, $role_id, $cb ) {

    # $role_id is role id
    if ( $role_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
        if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE id = ?], [$role_id] ) ) {
            $cb->( status 200, $role );
        }
        else {
            $cb->( status [ 404, qq[App role "$role_id" not found] ] );
        }
    }

    # $role id is app_id/role_name
    else {
        my ( $app_id, $role_name ) = split m[/]sm, $role_id;

        # $app_id is app id
        if ( $app_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app_role WHERE app_id = ? AND name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }

        # $app_id is app name
        else {
            if ( my $role = $self->dbh->selectrow( q[SELECT * FROM api_app, api_app_role WHERE api_app.name = ? AND api_app.id = api_app_role.app_id AND api_app_role.name = ?], [ $app_id, $role_name ] ) ) {
                $cb->( status 200, $role );
            }
            else {
                $cb->( status [ 404, qq[App role "$role_id" not found] ] );
            }
        }
    }

    return;
}

sub resolve_app_roles ( $self, $roles, $cb ) {
    my ( $resolved_roles, $errors );

    my $cv = AE::cv sub {
        if ($errors) {
            $cb->( status [ 400, 'Error resolving app roles' ], $errors );
        }
        else {
            $cb->( status 200, $resolved_roles );
        }

        return;
    };

    $cv->begin;

    for my $role_id ( $roles->@* ) {
        $cv->begin;

        $self->get_app_role(
            $role_id,
            sub ($res) {
                if ($res) {
                    $resolved_roles->{$role_id} = $res->{result};
                }
                else {
                    $errors->{$role_id} = $res->{reason};
                }

                $cv->end;

                return;
            }
        );
    }

    $cv->end;

    return;
}

sub get_app_roles ( $self, $app_id, $cb ) {

    # resolve app id
    $self->get_app(
        $app_id,
        sub ($app) {
            if ( !$app ) {
                $cb->($app);
            }
            else {
                my $roles = $self->dbh->selectall( q[SELECT * FROM api_app_role WHERE app_id = ?], [ $app->{result}->{id} ] );

                $cb->( 200, $roles // [] );
            }

            return;
        }
    );

    return;
}

sub get_all_roles ( $self, $cb ) {
    my $roles = $self->dbh->selectall(q[SELECT * FROM api_app_role]);

    $cb->( 200, $roles // [] );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 8, 22                | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
