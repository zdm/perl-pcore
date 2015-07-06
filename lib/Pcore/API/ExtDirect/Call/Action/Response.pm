package Pcore::API::Call::Action::Response;

use Pcore qw[-class];

with qw[Pcore::API::Call::Action];

has '+tid' => ( required => 1 );

has '+data' => ( isa => ArrayRef );

has success => ( is => 'rwp', isa => Bool, reader => 'is_success', default => 1 );
has meta    => ( is => 'rwp', isa => HashRef, predicate => 1 );
has message => ( is => 'rwp', isa => Str,     predicate => 1 );
has where   => ( is => 'rwp', isa => Str,     predicate => 1 );
has errors => ( is => 'rwp', isa => HashRef [Str], predicate => 1 );
has total => ( is => 'rwp', isa => PositiveOrZeroInt, predicate => 1 );

has is_response => ( is => 'lazy', isa => Bool, default => 1, init_arg => undef );

no Pcore;

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    P->hash->merge( $args, delete $args->{result} ) if $args->{result};

    delete $args->{data} if exists $args->{data} && !defined $args->{data};

    return $args;
}

sub TO_DATA {
    my $self = shift;

    my $json = {
        type   => $self->type,
        action => $self->action,
        method => $self->method,
        tid    => $self->tid,
        result => { success => $self->is_success ? $TRUE : $FALSE, },
    };

    $json->{result}->{meta}    = $self->meta    if $self->has_meta;
    $json->{result}->{message} = $self->message if $self->has_message;
    $json->{result}->{where}   = $self->where   if $self->has_where;
    $json->{result}->{errors}  = $self->errors  if $self->has_errors;
    $json->{result}->{total}   = $self->total   if $self->has_total;
    $json->{result}->{data}    = $self->data    if $self->has_data;

    return $json;
}

1;
__END__
=pod

=encoding utf8

=cut
