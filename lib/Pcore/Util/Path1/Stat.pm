package Pcore::Util::Path1::Stat;

use Pcore -role, -const;
use Fcntl qw[:mode];

const our $FILE_TEST_METHOD => {
    f => 'is_file',
    d => 'is_dir',
    l => 'is_link',
    b => 'is_blk',
    c => 'is_chr',
    p => 'is_fifo',
    S => 'is_sock',
};

use overload    #
  '-X' => sub {
    my $method = $FILE_TEST_METHOD->{ $_[1] };

    return $_[0]->stat->$method;
  };

# dev
# ino
# mode
# nlink
# uid
# gid
# rdev
# size
# atime
# mtime
# ctime
# btime
# blksize
# blocks
has stat => ( init_arg => undef );    # HashRef

sub stat ( $self, $cb = undef ) {     ## no critic qw[Subroutines: : ProhibitBuiltinHomonyms ] my $cv = defined wantarray ? P->cv : ();
    my $cv = defined wantarray ? P->cv : ();

    IO::AIO::aio_stat $self->{to_string}, sub ($error) {
        if ($error) {
            $self->set_status( [ 500, $! ] );

            undef $self->{stat};
        }
        else {
            $self->set_status(200);

            my $stat->@{qw[dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks]} = stat _;

            ( $stat->{atime}, $stat->{mtime}, $stat->{ctime}, $stat->{btime} ) = IO::AIO::st_xtime();

            $self->{stat} = $stat;
        }

        $self = $cb->($self) if defined $cb;

        $cv->($self) if defined $cv;

        return;
    };

    return defined $cv ? $cv->recv : ();
}

# -f
sub is_file ($self ) {
    return defined $self->{stat} ? S_ISREG( $self->{stat}->{mode} ) || 0 : undef;
}

# -d
sub is_dir ($self ) {
    return defined $self->{stat} ? S_ISDIR( $self->{stat}->{mode} ) || 0 : undef;
}

# -l
sub is_link ($self ) {
    return defined $self->{stat} ? S_ISLNK( $self->{stat}->{mode} ) || 0 : undef;
}

# -b
sub is_blk ($self ) {
    return defined $self->{stat} ? S_ISBLK( $self->{stat}->{mode} ) || 0 : undef;
}

# -c
sub is_chr ($self ) {
    return defined $self->{stat} ? S_ISCHR( $self->{stat}->{mode} ) || 0 : undef;
}

# -p
sub is_fifo ($self ) {
    return defined $self->{stat} ? S_ISFIFO( $self->{stat}->{mode} ) || 0 : undef;
}

# -S
sub is_sock ($self ) {
    return defined $self->{stat} ? S_ISSOCK( $self->{stat}->{mode} ) || 0 : undef;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1::Stat

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
