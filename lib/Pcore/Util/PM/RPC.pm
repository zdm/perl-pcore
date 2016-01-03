package Pcore::Util::PM::RPC;

use Pcore -class;
use Pcore::Util::PM::RPC::Proc;

has class   => ( is => 'ro', isa => Str,         required => 1 );
has args    => ( is => 'ro', isa => HashRef,     required => 1 );
has workers => ( is => 'ro', isa => PositiveInt, required => 1 );

has on_ready => ( is => 'ro', isa => Maybe [CodeRef] );
has on_exit  => ( is => 'ro', isa => Maybe [CodeRef] );

has _workers => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );

sub BUILDARGS ( $self, $args ) {
    $args->{args} //= {};

    $args->{workers} ||= P->sys->cpus_num;

    return $args;
}

sub BUILD ( $self, $args ) {
    my $cv = AE::cv {
        $self->on_ready->($self) if $self->on_ready;

        return;
    };

    for ( 1 .. $self->workers ) {
        $self->_create_worker($cv);
    }

    return;
}

sub _create_worker ( $self, $cv ) {
    $cv->begin;

    push $self->_workers->@*, Pcore::Util::PM::RPC::Proc->new(
        {   class    => $self->class,
            args     => $self->args,
            on_ready => sub ($worker) {
                $cv->end;

                return;
            }
        }
    );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
