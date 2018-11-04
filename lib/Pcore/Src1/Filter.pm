package Pcore::Src1::Filter;

use Pcore -role, -res, -const;
use Pcore::Src1 qw[:ACTION];

has file      => ( required => 1 );                           # InstanceOf ['Pcore::Src::File'], weaken
has data      => ( required => 1 );                           # ScalarRef
has has_kolon => ( is       => 'lazy', init_arg => undef );

const our $FILTER_METHOD => {
    $SRC_DECOMPRESS => 'decompress',
    $SRC_COMPRESS   => 'compress',
    $SRC_OBFUSCATE  => 'obfuscate',
};

sub run ( $self, $action ) {
    my $method = $FILTER_METHOD->{$action};

    return $self->$method;
}

sub src_cfg ($self) { return $self->{file}->cfg }

sub dist_cfg ($self) { return {} }

sub decompress ($self) { return res 200 }

sub compress ($self) { return res 200 }

sub obfuscate ($self) { return res 200 }

sub _build_has_kolon ($self) {
    return 1 if $self->{data}->$* =~ /<: /sm;

    return 1 if $self->{data}->$* =~ /^: /sm;

    return 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src1::Filter

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
