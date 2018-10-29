package Pcore::Util::Path::Dir;

use Pcore -role;
use Pcore::Util::Scalar qw[is_plain_coderef];
use Fcntl qw[];

sub read_dir ( $self, @ ) {
    return if !-d $self;

    my %args = (
        max_depth   => 1,        # 0 - unlimited
        follow_link => 1,
        is_dir      => 1,
        is_file     => 1,
        is_sock     => 1,
        is_link     => undef,    # undef - do not check, 1 - add links only, 0 - skip links
        @_[ 1 .. $#_ ]
    );

    my $abs_base = $self->to_abs->encoded;

    my $prefix = $args{abs} ? $abs_base : '.';

    my $res;

    my $read = sub ( $dir, $depth ) {
        opendir my $dh, "$abs_base/$dir" or die qq[Can't open dir "$abs_base/$dir"];

        my @paths = readdir $dh or die $!;

        closedir $dh or die $!;

        for my $file (@paths) {
            next if $file eq '.' || $file eq '..';

            my $abs_path = "$abs_base/$dir/$file";

            my ( $stat, $lstat );

            my $push = 1;

            if ( defined $args{is_link} ) {
                $lstat //= ( lstat $abs_path )[2] & Fcntl::S_IFMT;

                if ( $lstat == Fcntl::S_IFLNK ) {
                    $push = 0 if !$args{is_link};
                }
                else {
                    $push = 0 if $args{is_link};
                }
            }

            if ( $push && !$args{is_file} ) {
                $stat //= ( stat $abs_path )[2] & Fcntl::S_IFMT;

                $push = 0 if $stat == Fcntl::S_IFREG;
            }

            if ( $push && !$args{is_dir} ) {
                $stat //= ( stat $abs_path )[2] & Fcntl::S_IFMT;

                $push = 0 if $stat == Fcntl::S_IFDIR;
            }

            if ( $push && !$args{is_sock} ) {
                $stat //= ( stat $abs_path )[2] & Fcntl::S_IFMT;

                $push = 0 if $stat == Fcntl::S_IFSOCK;
            }

            if ($push) {
                my $path = "$prefix/$dir/$file";

                if ($MSWIN) {
                    state $enc = Encode::find_encoding($Pcore::WIN_ENC);

                    $path = $enc->decode( $path, Encode::FB_CROAK );
                }

                push $res->@*, $self->new($path);
            }

            if ( !$args{max_depth} || $depth < $args{max_depth} ) {
                $stat //= ( stat $abs_path )[2] & Fcntl::S_IFMT;

                if ( $stat == Fcntl::S_IFDIR ) {
                    if ( !$args{follow_link} ) {
                        $lstat //= ( lstat $abs_path )[2] & Fcntl::S_IFMT;

                        next if $lstat == Fcntl::S_IFLNK;
                    }

                    __SUB__->( "$dir/$file", $depth + 1 );
                }
            }
        }

        return;
    };

    $read->( '', 1 );

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 7                    | Subroutines::ProhibitExcessComplexity - Subroutine "read_dir" with high complexity score (30)                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 101                  | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 10                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path::Dir

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
