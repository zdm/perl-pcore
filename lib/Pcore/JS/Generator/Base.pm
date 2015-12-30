package Pcore::JS::Generator::Base;

use Pcore -role;

requires qw[as_js];

has id => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_id {
    my $self = shift;

    state $c = 1;

    my $id = ++$c;

    return $id;
}

sub FREEZE {
    my $self = shift;

    $Pcore::JS::Generator::CACHE->{ $self->id } = $self;

    return $self->id;
}

sub generate_js {
    my $self = shift;
    my $data = shift;

    my $js = \P->data->to_json( $data, ascii => 0, latin1 => 0, utf8 => 0, ( $Pcore::JS::Generator::READABLE ? ( pretty => 1, canonical => 1 ) : () ) );
    $js->$* =~ s/[(]"Pcore::JS::Generator::[[:alpha:]]+"[)]\[(\d+)\]/$Pcore::JS::Generator::CACHE->{$1}->as_js/smge;

    return $js;
}

1;
__END__
=pod

=encoding utf8

=cut
