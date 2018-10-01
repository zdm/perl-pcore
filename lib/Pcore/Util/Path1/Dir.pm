package Pcore::Util::Path1::Dir;

use Pcore -role;
use Pcore::Util::Scalar qw[is_plain_coderef];

# abs, recursive, dir, file
sub read_dir ( $self, %args ) {
    my $res;

    $args{dir}  //= 1;
    $args{file} //= 1;

    # must be without trailing '/'
    my $base = $self->to_abs->{to_string};

    my $prefix = $args{abs} ? $self->to_abs->{to_string} . '/' : '';

    my $read = sub ($dir) {
        my $dir_path = "${base}$dir";

        opendir my $dh, $dir_path or die qq[Can't open dir "$dir_path"];

        my @paths = readdir $dh or die $!;

        closedir $dh or die $!;

        for my $path (@paths) {
            next if $path eq '.' || $path eq '..';

            my $fpath = "${dir_path}$path";

            my $rel_dir = substr $dir, 1;

            if ( -d $fpath ) {
                push $res->@*, "${prefix}${rel_dir}$path" if $args{dir};

                __SUB__->("${dir}$path/") if $args{recursive};
            }
            elsif ( -f _ ) {
                push $res->@*, "${prefix}${rel_dir}$path" if $args{file};
            }
        }

        return;
    };

    $read->('/');

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 16                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
