package Pcore::App::API::Session;

use Pcore -class;

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API'], required => 1 );
has uid     => ( is => 'ro', isa => PositiveInt, required => 1 );
has role_id => ( is => 'ro', isa => PositiveInt, required => 1 );

has allowed_methods => ( is => 'lazy', isa => HashRef, init_arg => undef );

# TODO resolve role_id -> methods
sub _build_allowed_methods ($self) {
    my $methods->@{ keys $self->api->map->%* } = ();

    return $methods;
}

sub is_root ($self) {
    return $self->{uid} == 1;
}

sub api_call ( $self, $method_id, @ ) {
    my $cb = $_[-1];

    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $on_finish;

    $on_finish = sub ( $status, $reason = undef, $result = undef ) {
        undef $on_finish;

        my $api_res;

        if ( ref $status ) {
            $api_res = $status;
        }
        else {
            $api_res = Pcore::API::Response->new( { status => $status, defined $reason ? ( reason => $reason ) : () } );

            $api_res->{result} = $result;
        }

        $cb->($api_res) if $cb;

        $blocking_cv->($api_res) if $blocking_cv;

        return;
    };

    my $method_cfg = $self->{api}->map->{$method_id};

    if ( !$method_cfg ) {
        $on_finish->( 404, qq[API method "$method_id" was not found] );
    }
    else {
        if ( $self->{uid} != 1 && !exists $self->allowed_methods->{$method_id} ) {
            $on_finish->( 401, qq[Unauthorized access to API method "$method_id"] );
        }
        else {
            my $obj = bless { api => $self->{spi}, api_session => $self }, $method_cfg->{class_name};

            my $method_name = $method_cfg->{method_name};

            eval { $obj->$method_name( $on_finish, splice( @_, 4, -1 ) ) };

            if ($@) {
                $@->sendlog;

                $on_finish->( 500, qq[Error executing API method "$method_id"] ) if $on_finish;
            }
        }
    }

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 13                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 64                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 64                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Session

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
