package Pcore::API::Call;

use Pcore -class;
use Pcore::API::Call::Action::Request;
use Pcore::API::Call::Action::Response;

has _actions => ( is => 'lazy', isa => ArrayRef [ InstanceOf ['Pcore::API::Call::Action'] ], default => sub { [] }, init_arg => undef );
has _index => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

has has_uploads => ( is => 'lazy', isa => Bool, clearer => 1, init_arg => undef );

has _tid => ( is => 'rwp', isa => NegativeInt, default => -1, init_arg => undef );

sub BUILDARGS {
    my $self = shift;

    my $actions;

    if (@_) {
        if ( !ref $_[0] ) {    # single action in internal format
            $actions = [ \@_ ];
        }
        elsif ( ref $_[0] eq 'HASH' ) {    # single action in hash format
            $actions = [ $_[0] ];
        }
        elsif ( ref $_[0] eq 'ARRAY' ) {
            if ( ref $_[0]->[0] eq 'HASH' ) {    # multiple actions in hash format
                $actions = $_[0];
            }
            else {
                $actions = \@_;                  # multiple actions in internal array format
            }
        }
        else {
            die;
        }

        return { actions => $actions };
    }
    else {
        return {};                               # no actions
    }
}

sub BUILD {
    my $self = shift;
    my $args = shift;

    if ( $args->{actions} ) {
        for my $action ( $args->{actions}->@* ) {
            if ( ref $action eq 'ARRAY' ) {      # action in internal format
                my $action_args = {};

                ( $action_args->{action}, $action_args->{method}, $action_args->{tid} ) = split /#/sm, shift $action->@*;

                delete $action_args->{tid} if !defined $action_args->{tid};

                $action_args->{data} = shift $action->@*;

                P->hash->merge( $action_args, { $action->@* } ) if $action->@*;

                $self->add_action($action_args);
            }
            else {    # HashRef or blessed action object
                $self->add_action($action);
            }
        }
    }

    return;
}

sub add_action {
    my $self   = shift;
    my $action = shift;    # HashRef or blessed

    if ( ref $action eq 'HASH' ) {
        if ( $action->{result} ) {
            $action = Pcore::API::Call::Action::Response->new($action);
        }
        else {
            $action = Pcore::API::Call::Action::Request->new($action);
        }
    }

    $action->_set_tid( $self->_get_tid ) if !$action->has_tid;

    die q[Duplicate action TID] if exists $self->_index->{ $action->tid };

    $self->_index->{ $action->tid } = $action;

    push $self->_actions, $action;

    $self->clear_has_uploads;

    return;
}

sub _get_tid {
    my $self = shift;

    my $tid = $self->_tid;

    $self->_set__tid( $self->_tid - 1 );

    return $tid;
}

sub _build_has_uploads {
    my $self = shift;

    for ( $self->_actions->@* ) {
        return 1 if $_->can('has_uploads') && $_->has_uploads;
    }

    return 0;
}

sub actions {
    my $self = shift;

    if (wantarray) {
        my @tids = sort keys $self->_actions_index->%*;

        return @tids;
    }
    else {
        return $self->_actions;
    }
}

sub action {
    my $self = shift;
    my $tid  = shift;

    if ( defined $tid ) {
        return $self->_index->{$tid};
    }
    else {
        return $self->_actions->[0];
    }
}

sub TO_DATA {
    my $self = shift;

    return $self->_actions->@* == 1 ? $self->_actions->[0] : $self->_actions;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 123                  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
