package Pcore::HTTP::Response;

use Pcore -class;
use Pcore::Lib::Scalar qw[is_plain_scalarref];

with qw[Pcore::Lib::Result::Role];

has url => ();

has version => ();
has headers => ();
has data    => ();

has content_length => 0;
has is_redirect    => ();
has decoded_data   => ( is => 'lazy' );
has tree           => ( is => 'lazy' );
has redirects      => ();                 # ArrayRef of intermadiate redirects

sub _build_decoded_data ($self) {
    return if !$self->{data};

    return if !is_plain_scalarref $self->{data};

    require HTTP::Message;

    return HTTP::Message->new( [ 'Content-Type' => $self->{headers}->{'content-type'} ], $self->{data}->$* )->decoded_content( raise_error => 1 );
}

sub _build_tree ($self) {
    return if !$self->{data};

    return if !is_plain_scalarref $self->{data};

    # return P->html->tree( $self->{data}->$* );

    return P->html->tree( $self->decoded_data, encoding => HTML5::DOM::Encoding->UTF_8 );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
