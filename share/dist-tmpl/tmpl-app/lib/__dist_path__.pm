package <: $module_name :> v0.0.0;

use Pcore -dist, -class, -const;
use <: $module_name ~ "::Const qw[:CONST]" :>;
use <: $module_name ~ "::Util" :>;
use Pcore::RPC::Hub;

has cfg => ( is => 'ro', isa => HashRef, required => 1 );

has util => ( is => 'ro', isa => InstanceOf ['<: $module_name :>::Util'], init_arg => undef );
has rpc  => ( is => 'ro', isa => InstanceOf ['Pcore::RPC::Hub'],          init_arg => undef );

with qw[Pcore::App];

const our $APP_API_ROLES => [ 'admin', 'user' ];

sub run ( $self, $cb ) {

    # update schema
    ( $self->{util} = <: $module_name ~ "::Util" :>->new )->update_schema(
        $self->{cfg}->{_}->{db},
        sub ($res) {

            # run RPC
            ( $self->{rpc} = Pcore::RPC::Hub->new )->run_rpc(
                [   {   type           => '<: $module_name :>::RPC::RPC1',
                        workers        => 1,
                        token          => undef,
                        listen_events  => undef,
                        forward_events => ['APP.SETTINGS_UPDATED'],
                        buildargs      => {                                  #
                            cfg => $self->{cfg},
                        },
                    },
                ],
                sub {

                    # load settings
                    $self->{util}->load_settings( sub ($res) {

                        # app ready
                        $cb->();

                        return;
                    } );

                    return;
                }
            );

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
## |    3 | 4, 5                 | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 10, 26               | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 74                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 78 does not match the package declaration       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

<: $module_name :>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=head1 AUTHOR

<: $author :> <<: $author_email :>>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) <: $copyright_year :> by <: $copyright_holder :>.

=cut
