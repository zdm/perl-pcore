package Pcore::Util::Path1::Stat;

use Pcore -role, -const;
use Fcntl qw[];
use Clone qw[];

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

    delete $_[0]->{stat};
    delete $_[0]->{_stat_type};

    return $_[0]->$method;
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
has stat       => ( init_arg => undef );    # HashRef
has _stat_type => ( init_arg => undef );

our $STAT_CB = {};

sub stat ( $self, $cb = undef ) {           ## no critic qw[Subroutines: : ProhibitBuiltinHomonyms ] my $cv = defined wantarray ? P->cv : ();
    my $cv = defined wantarray ? P->cv : ();

    my $on_finish = sub ($self) {
        $self = $cb->($self) if defined $cb;

        $cv->($self) if defined $cv;

        return;
    };

    my $path = $self->{to_string};

    push $STAT_CB->{$path}->@*, [ $self, $on_finish ];

    return if $STAT_CB->{$path}->@* > 1;

    IO::AIO::aio_stat $path, sub ($error) {
        my $stat;

        if ( !$error ) {
            $stat->@{qw[dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks]} = stat _;

            ( $stat->{atime}, $stat->{mtime}, $stat->{ctime}, $stat->{btime} ) = IO::AIO::st_xtime();
        }

        for my $cb ( delete( $STAT_CB->{$path} )->@* ) {
            delete $cb->[0]->{_stat_type};

            # ok
            if ( defined $stat ) {
                $cb->[0]->set_status(200);

                $cb->[0]->{stat} = Clone::clone($stat);
            }

            # error
            else {
                $cb->[0]->set_status( [ 500, $! ] );

                delete $cb->[0]->{stat};
            }

            $cb->[1]->( $cb->[0] );
        }

        return;
    };

    return defined $cv ? $cv->recv : ();
}

my $method_type = {
    is_file => Fcntl::S_IFREG,
    is_dir  => Fcntl::S_IFDIR,
    is_lnk  => Fcntl::S_IFLNK,
    is_blk  => Fcntl::S_IFBLK,
    is_chr  => Fcntl::S_IFCHR,
    is_fifo => Fcntl::S_IFIFO,
    is_sock => Fcntl::S_IFSOCK,
};

while ( my ( $method, $type ) = each $method_type->%* ) {
    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
sub $method (\$self ) {

    # stat type is not cached
    if ( !defined \$self->{_stat_type} ) {

        # get stat
        my \$res = !defined \$self->{stat} ? \$self->stat : ();

        # get stat error
        return if !defined \$self->{stat};

        \$self->{_stat_type} = Fcntl::S_IFMT( \$self->{stat}->{mode} );
    }

    return \$self->{_stat_type} == $type;
}
PERL
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 109                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
