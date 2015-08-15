package Pcore::Util::Text::Table;

use Pcore qw[-class];
use Text::ASCIITable qw[];    ## no critic qw(Modules::ProhibitEvilModules)

has row_line => ( is => 'ro', isa => Bool, default => 1 );
has _protect_spaces => ( is => 'rw', isa => Bool, default => 0, init_arg => undef );
has _obj => ( is => 'lazy', isa => InstanceOf ['Text::ASCIITable'], init_arg => undef );

sub _build__obj {
    my $self = shift;

    return Text::ASCIITable->new( { drawRowLine => $self->row_line, allowANSI => 1, utf8 => 0 } );
}

sub set_cols {
    my $self = shift;

    return $self->_obj->setCols(@_);
}

sub set_col_width {
    my $self = shift;

    return $self->_obj->setColWidth(@_);
}

sub align_col {
    my $self = shift;

    return $self->_obj->alignCol(@_);
}

sub add_row {
    my $self = shift;

    return $self->_obj->addRow(@_);
}

sub add_row_line {
    my $self = shift;

    return $self->_obj->addRowLine(@_);
}

sub protect_spaces {
    my $self = shift;
    my $str  = shift;

    $self->_protect_spaces(1);

    $str =~ s/\t/♠♠♠♠/smg;
    $str =~ s/\h/♠/smg;

    return $str;
}

sub render {
    my $self = shift;

    my $res = $self->_obj->draw(
        [ q[┌], q[┐], q[─], q[┬] ],    # top line
        [ q[│], q[│], q[│] ],          # header row
        [ q[╞], q[╡], q[═], q[╪] ],    # header row separator
        [ q[│], q[│], q[│] ],          # row repeated for each row
        [ q[└], q[┘], q[─], q[┴] ],    # bottom line
        [ q[├], q[┤], q[─], q[┼] ],    # only used if drawRowLine is enabled and to render addRowLine call
    );

    $res =~ s/♠/ /smg if $self->_protect_spaces;

    return $res;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Text::Table

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
