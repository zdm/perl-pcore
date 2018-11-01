package Pcore::Util::File1::TempFile;

use Pcore -class;

extends qw[Pcore::Util::Path];

our @DEFERRED_UNLINK;

END { unlink @DEFERRED_UNLINK if @DEFERRED_UNLINK }    ## no critic qw[InputOutput::RequireCheckedSyscalls]

sub DESTROY ($self) {
    unlink $self->{path};                              ## no critic qw[InputOutput::RequireCheckedSyscalls]

    push @DEFERRED_UNLINK, $self->encoded if -f $self;

    return;
}

around new => sub ( $orig, $self, @args ) { return $self->SUPER::new(@args) };

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File1::TempFile

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
