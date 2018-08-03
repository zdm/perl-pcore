package Pcore::HTTP::Response;

use Pcore -class;
use Pcore::Util::Scalar qw[is_plain_coderef is_plain_scalarref];

with qw[Pcore::Util::Result::Status];

has url => ();

has version => ();
has headers => ();
has data    => ();

has content_length => 0;
has is_redirect    => ();
has decoded_body   => ( is => 'lazy' );
has tree           => ( is => 'lazy' );
has redirects      => ();                 # ArrayRef of intermadiate redirects

sub BUILDARGS ( $self, $args ) {
    return $args;
}

sub _build_decoded_body ($self) {
    return if !$self->{data};

    return if !is_plain_scalarref $self->{data};

    state $init = !!require HTTP::Message;

    return HTTP::Message->new( [ 'Content-Type' => $self->{headers}->{CONTENT_TYPE} ], $self->{data}->$* )->decoded_content( raise_error => 1, ref => 1 );
}

sub _build_tree ($self) {
    return if !$self->{data};

    return if !is_plain_scalarref $self->{data};

    state $init = !!require HTML::TreeBuilder::LibXML;

    my $tree = HTML::TreeBuilder::LibXML->new;

    $tree->parse( $self->decoded_data->$* );

    $tree->eof;

    return $tree;
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
