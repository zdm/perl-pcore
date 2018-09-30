package Pcore::Util::Path1::Dir;

use Pcore -role;
use IO::AIO qw[];
use Pcore::Util::Scalar qw[is_plain_coderef];

sub read_dir ( $self, @ ) {
    my $cb = is_plain_coderef $_[-1] ? shift : ();

    my $cv = defined wantarray ? P->cv : ();

    my %args = (
        recursive => 0,
        @_[ 1 .. $#_ ]
    );

    # IO::AIO::READDIR_DENTS
    # IO::AIO::READDIR_DIRS_FIRST
    # IO::AIO::READDIR_STAT_ORDER
    my $flags = IO::AIO::READDIR_DENTS | IO::AIO::READDIR_DIRS_FIRST;

    IO::AIO::aio_readdirx $self->{to_string}, $flags, sub ( $res, $flags ) {
        $res = $cb->($res) if defined $cb;

        $cv->($res) if defined $cv;

        return;
    };

    return defined $cv ? $cv->recv : ();
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1::Dir

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
