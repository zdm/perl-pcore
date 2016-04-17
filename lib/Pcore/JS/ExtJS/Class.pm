package Pcore::JS::ExtJS::Class;

use Pcore -class;

with qw[Pcore::JS::Generator];

has ext_req => ( is => 'ro', isa => InstanceOf ['Pcore::JS::ExtJS::Request'], required => 1, weak_ref => 1 );
has extend => ( is => 'ro', isa => InstanceOf ['Pcore::JS::ExtJS::Class::Descriptor'], required => 1 );
has alias_ns => ( is => 'ro', isa => Maybe [ Enum [ keys $Pcore::JS::ExtJS::Class::Descriptor::EXT->{alias_ns}->%* ] ] );

has cfg => ( is => 'lazy', default => sub { {} }, init_arg => undef );

has _generated_as_class => ( is => 'rwp', isa => Bool, default => 0, init_arg => undef );

sub BUILD {
    my $self = shift;
    my $args = shift;

    # automatically add base class to requires
    push $args->{requires}->@*, $self->extend;

    $self->ext_req->add_requires( $args->{requires} );

    $self->apply( $args->{cfg} ) if $args->{cfg};

    return;
}

sub apply {
    my $self = shift;

    P->hash->merge( $self->cfg, @_ );

    return $self;
}

sub TO_DATA {
    my $self = shift;

    my $alias_ns;

    # try to determine alias ns by base class alias
    if ( my $base_class_alias = $self->extend->ext_alias ) {
        $alias_ns = $base_class_alias =~ s/[.][^.]+\z//smr;
    }

    $alias_ns ||= $self->alias_ns;

    my $type_attr;
    $type_attr = $alias_ns eq 'widget' ? 'xtype' : 'type' if $alias_ns;

    if ( $self->_generated_as_class ) {
        if ($alias_ns) {

            # automatically generate class alias
            $self->cfg->{alias} = $alias_ns . q[.] . $self->ext_req->type;

            # remove type attribute, which is used only for inline class declaration
            delete $self->cfg->{$type_attr};
        }
    }
    else {
        if ($alias_ns) {
            $self->cfg->{$type_attr} = $self->extend->type;
        }
        else {
            die q[Can't automatically determine alias namespace for class "] . $self->extend->class . q[" during declarative class generation. You should manually specify "alias_ns" attr in "ext_define" call];
        }
    }

    return $self->cfg;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 9                    | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
