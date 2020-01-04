package <: $module_name :>;

use Pcore -dist, -class, -const, -res, -export;
use <: $module_name ~ "::Const qw[]" :>;
use <: $module_name ~ "::Util" :>;

our $EXPORT = { PERMISSIONS => [qw[$PERMISSIONS_ADMIN $PERMISSIONS_USER]], };

has util => ( init_arg => undef );    # InstanceOf ['<: $module_name :>::Util']

with qw[Pcore::App];

const our $PERMISSIONS_ADMIN => 'admin';
const our $PERMISSIONS_USER  => 'user';
const our $PERMISSIONS       => [ $PERMISSIONS_ADMIN, $PERMISSIONS_USER ];

const our $NODE_REQUIRES => {

    # '<: $module_name ~ "::Node::SystemLog" :>' => undef,
    # '<: $module_name ~ "::Node::Worker" :>'    => undef,
};

sub NODE_ON_EVENT ( $self, $ev ) {
    P->forward_event($ev);

    return;
}

sub NODE_ON_RPC ( $self, $ev ) {
    return;
}

# PERMISSIONS
sub get_permissions ($self) {
    return $PERMISSIONS;
}

# RUN
sub run ( $self ) {
    $self->{util} = <: $module_name ~ "::Util" :>->new( app => $self );

    # update schema
    print 'Updating DB schema ... ';
    say( my $res = $self->{util}->update_schema( $self->{cfg}->{db} ) );
    return $res if !$res;

    # load settings
    $res = $self->{api}->settings_load;

    # run local nodes
    print 'Starting nodes ... ';
    say $self->{node}->run_node(

        # {   type      => '<: $module_name :>::Node::Worker',
        #     workers   => 1,
        #     buildargs => {
        #         cfg  => $self->{cfg},
        #         util => $self->{util},
        #     },
        # },
        # {   type      => '<: $module_name :>::Node::SystemLog',
        #     workers   => 1,
        #     buildargs => {
        #         store_interval => 0,
        #         cfg            => $self->{cfg},
        #         util           => { settings => $self->{api}->{settings} },
        #     },
        # },
    );

    $self->{node}->wait_online;

    # app ready
    return res 200;
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
## |    1 | 79                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 83 does not match the package declaration       |
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
