package Pcore::App::API::Backend::Local::sqlite::App;

use Pcore -role, -promise, -status;

sub get_app ( $self, $app_id, $cb ) {
    if ( $app_id =~ /\A\d+\z/sm ) {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE id = ?], [$app_id] ) ) {
            $cb->( status 200, app => $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }
    else {
        if ( my $app = $self->dbh->selectrow( q[SELECT * FROM api_app WHERE name = ?], [$app_id] ) ) {
            $cb->( status 200, app => $app );
        }
        else {

            # app not found
            $cb->( status [ 404, 'App not found' ] );
        }
    }

    return;
}

sub set_app_enabled ( $self, $app_id, $enabled, $cb ) {
    $self->get_app(
        $app_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);

                return;
            }

            my $app = $res->{app};

            if ( ( $enabled && !$app->{enabled} ) || ( !$enabled && $app->{enabled} ) ) {
                if ( $self->dbh->do( q[UPDATE OR IGNORE api_app SET enabled = ? WHERE id = ?], [ !!$enabled, $app->{id} ] ) ) {
                    $cb->( status 200 );
                }
                else {
                    $cb->( status [ 500, 'Error set app enabled' ] );
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
