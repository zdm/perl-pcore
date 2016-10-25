package Pcore::App::API::Backend::Local::sqlite::App;

use Pcore -role, -promise, -status;
use Pcore::Util::UUID qw[uuid_str];

sub get_app ( $self, $app_id, $cb ) {

    # $app_id is id
    if ( $app_id =~ /\A[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\z/sm ) {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE id = ?], [$app_id] ) ) {
            $cb->( status 200, $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }

    # $app_id is name
    else {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_id] ) ) {
            $cb->( status 200, $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }

    return;
}

sub create_app ( $self, $name, $desc, $cb ) {

    # validate app name
    if ( !$self->{app}->{api}->validate_name($name) ) {
        $cb->( status [ 400, 'App name is not valid' ] );

        return;
    }

    # create app
    my $created = $self->dbh->do( q[INSERT OR IGNORE INTO api_app (id, name, desc, created_ts) VALUES (?, ?, ?, ?)], [ uuid_str, $name, $desc, time ] );

    $self->get_app(
        $name,
        sub ($res) {
            if ($res) {
                $cb->( status $created ? 201 : 304, $res->{result} );
            }
            else {
                $cb->( status [ 400, 'Error creating app' ] );
            }

            return;
        }
    );

    return;
}

sub remove_app ( $self, $app_id, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            if ( $self->dbh->do( q[DELETE OR IGNORE FROM api_app WHERE id = ?], [ $res->{app}->{id} ] ) ) {
                $cb->( status 200 );
            }
            else {
                $cb->( status [ 404, 'Error removing app' ] );
            }

            return;
        }
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 9                    | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local::sqlite::App

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
