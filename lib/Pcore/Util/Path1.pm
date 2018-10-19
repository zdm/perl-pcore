package Pcore::Util::Path1;

use Pcore -class, -const, -res;
use Clone qw[];
use Cwd qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Pcore::Util::Data qw[from_uri_utf8 to_uri_path];
use Pcore::Util::Scalar qw[is_blessed_hashref];

use overload
  q[""]    => sub { $_[0]->{to_string} },
  fallback => 1;

with qw[
  Pcore::Util::Result::Status
  Pcore::Util::Path1::Dir
  Pcore::Util::Path1::Poll
];

has to_string     => ();
has volume        => ();
has dirname       => ();
has filename      => ();
has filename_base => ();
has suffix        => ();

has is_abs => ();

has _to_url => ( init_arg => undef );

has IS_PCORE_PATH => ( 1, init_arg => undef );

around new => sub ( $orig, $self, $path = undef, %args ) {
    if ( !defined $path ) {
        return bless { to_string => '' }, $self;
    }

    if ( is_blessed_hashref $path ) {
        return $path if $path->{IS_PCORE_PATH};

        $path = "$path";
    }

    $self = bless { to_string => $path }, __PACKAGE__;

    if ($MSWIN) {
        if ( $path =~ /\A([a-z]):/smi ) {
            $self->{volume} = lc $1;
            $self->{is_abs} = 1;
        }
    }
    else {
        if ( substr( $path, 0, 1 ) eq '/' ) {
            $self->{is_abs} = 1;
        }
    }

    return $self;
};

sub to_string ($self) {
    if ( !exists $self->{to_string} ) {

    }

    return $self->{to_string};
}

sub clone ($self) {
    return Clone::clone($self);
}

sub to_uri ($self) {
    if ( !exists $self->{_to_uri} ) {
        my $path = $self->{to_string};

        # Relative Reference: https://tools.ietf.org/html/rfc3986#section-4.2
        # A path segment that contains a colon character (e.g., "this:that")
        # cannot be used as the first segment of a relative-path reference, as
        # it would be mistaken for a scheme name.  Such a segment must be
        # preceded by a dot-segment (e.g., "./this:that") to make a relative-
        # path reference.
        # $path = "./$path" if $path =~ m[\A[^/]*:]sm;

        if ( $self->{volume} ) {
            $self->{_to_uri} = to_uri_path "/$path";
        }
        elsif ( $path =~ m[\A[^/]*:]sm ) {
            $self->{_to_uri} = to_uri_path "./$path";
        }
        else {
            $self->{_to_uri} = to_uri_path $path;
        }
    }

    return $self->{_to_uri};
}

# TODO error on empty path
sub to_abs ( $self, $base = undef ) {

    # path is already absolute
    return defined wantarray ? $self->clone : () if $self->{is_abs};

    if ( !defined $base ) {
        $base = Cwd::getcwd();
    }
    else {
        $base = $self->new($base)->to_abs->{to_string};
    }

    if ( defined wantarray ) {
        return $self->new("$base/$self->{to_string}");
    }
    else {
        $self->{to_string} = "$base/$self->{to_string}";
    }

    return;
}

# TODO error on empty path
sub to_realpath ( $self ) {
    my $realpath = Cwd::realpath( $self->{to_string} );

    if ( defined wantarray ) {
        return $self->new($realpath);
    }
    else {
        $self->{to_string} = $realpath;

        return;
    }
}

sub volume ( $self, $volume = undef ) {
    return;
}

# sub TO_DUMP {
#     my $self = shift;

#     my $res;
#     my $tags;

#     $res = qq[path: "$self->{to_string}"];

#     # $res .= qq[\nMIME type: "] . $self->mime_type . q["] if $self->mime_type;

#     return $res, $tags;
# }

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 34                   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 46                   | RegularExpressions::ProhibitEnumeratedClasses - Use named character classes ([a-z] vs. [[:lower:]])            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
