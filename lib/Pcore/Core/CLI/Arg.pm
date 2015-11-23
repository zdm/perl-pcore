package Pcore::Core::CLI::Arg;

use Pcore qw[-class -const];

has name => ( is => 'ro', isa => Str, required => 1 );
has type => ( is => 'ro', isa => Maybe [ Enum [qw[Str Int Num Path Dir File]] ] );    # argument is required if type is present
has required => ( is => 'ro', isa => Bool, default => 1 );
has slurpy   => ( is => 'ro', isa => Bool, default => 0 );

has type_desc => ( is => 'lazy', isa => Str, init_arg => undef );
has spec      => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

const our $TYPE_VALIDATOR => {
    Str => sub ($val) {
        return 1;
    },
    Int => sub ($val) {
        return $val =~ /\A[+-]*\d+\z/sm ? 1 : 0;
    },
    Num => sub ($val) {
        return $val =~ /\A[+-]*\d*[.]?\d*\z/sm ? 1 : 0;
    },
    Path => sub ($val) {
        return -e $val;
    },
    Dir => sub ($val) {
        return -d $val;
    },
    File => sub ($val) {
        return -f $val;
    },
};

sub _build_type_desc ($self) {
    return uc $self->name =~ s/_/-/smgr;
}

sub validate ( $self, $val ) {
    return $TYPE_VALIDATOR->{ $self->type }->($val);
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Arg

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
