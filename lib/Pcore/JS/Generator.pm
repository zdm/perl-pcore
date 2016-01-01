package Pcore::JS::Generator;

use Pcore -role;
use Pcore::JS::Generator::Raw;
use Pcore::JS::Generator::Func;
use Pcore::JS::Generator::Call;

our $CACHE    = {};
our $READABLE = 0;

sub js_raw {
    my $self = shift;

    return Pcore::JS::Generator::Raw->new( { body => shift } );
}

sub js_func {
    my $self = shift;

    my $func_name;
    my $func_args;
    my $func_body;

    if ( @_ > 1 ) {
        if ( ref $_[0] eq 'ARRAY' ) {
            $func_args = $_[0];
            $func_body = $_[1];
        }
        else {
            $func_name = $_[0];
            $func_args = $_[1];
            $func_body = $_[2];
        }
    }
    else {
        $func_body = $_[0];
    }

    return Pcore::JS::Generator::Func->new(
        {   func_name => $func_name,
            func_args => $func_args,
            func_body => $func_body,

        }
    );
}

sub js_call {
    my $self = shift;

    return Pcore::JS::Generator::Call->new(
        {   func_name => shift,
            func_args => [@_],
        }
    );
}

sub js_generate {
    my $self = shift;
    my $data = shift;
    my %args = (
        readable => 0,
        @_,
    );

    local $Pcore::JS::Generator::CACHE = {};
    local $Pcore::JS::Generator::READABLE = 1 if $args{readable};

    my $js = P->data->to_json( $data, readable => $args{readable} );

    $js->$* =~ s/[(]"Pcore::JS::Generator::[[:alpha:]]+"[)]\[(\d+)\]/$CACHE->{$1}->as_js/smge;

    $js->$* .= q[;];

    return $js;
}

1;
__END__
=pod

=encoding utf8

=cut
