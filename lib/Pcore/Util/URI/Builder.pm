package Pcore::Util::URI::Builder;

use Pcore;
use Pcore::Util::URI::_generic;

no Pcore;

sub NEW ( $self, $uri, $base = undef, @ ) {
    my $args = _parse($uri);

    my $scheme = $args->{scheme};

    # https://tools.ietf.org/html/rfc3986#section-5
    # if URI has no scheme and base URI is specified - merge with base URI
    if ( $args->{scheme} eq q[] && defined $base ) {

        # parse base URI
        if ( !ref $base ) {
            $base = _parse($base);
        }
        else {
            $base = {
                scheme    => $base->_scheme,
                authority => $base->_authority,
                path      => $base->_path,
                query     => $base->_query,
                fragment  => $base->_fragment,
            };
        }

        return if $base->{scheme} eq q[];

        $scheme = $base->{scheme};
    }

    state $scheme_cache = {    #
        q[] => 'Pcore::Util::URI::_generic',
    };

    if ( !exists $scheme_cache->{$scheme} ) {
        try {
            $scheme_cache->{$scheme} = P->class->load( $scheme, ns => 'Pcore::Util::URI' );
        }
        catch {
            $scheme_cache->{$scheme} = 'Pcore::Util::URI::_generic';
        };
    }

    return $scheme_cache->{$scheme}->NEW( $args, $base );
}

sub _parse ( $uri, @ ) {
    my %args = (
        has_authority => 0,
        scheme        => q[],
        authority     => q[],
        path          => q[],
        query         => q[],
        fragment      => q[],
    );

    # fragment
    if ( ( my $fragment_idx = index $uri, q[#] ) != -1 ) {
        $args{fragment} = substr $uri, $fragment_idx, length $uri, q[];

        substr $args{fragment}, 0, 1, q[];    # remove "#" from fragment
    }

    # query
    if ( ( my $query_idx = index $uri, q[?] ) != -1 ) {
        $args{query} = substr $uri, $query_idx, length $uri, q[];

        substr $args{query}, 0, 1, q[];       # remove "?" from query
    }

    # If a URI contains an authority component, then the path component
    # must either be empty or begin with a slash ("/") character.  If a URI
    # does not contain an authority component, then the path cannot begin
    # with two slash characters ("//").  In addition, a URI reference
    # (Section 4.1) may be a relative-path reference, in which case the
    # first path segment cannot contain a colon (":") character.  The ABNF
    # requires five separate rules to disambiguate these cases, only one of
    # which will match the path substring within a given URI reference.  We
    # use the generic term "path component" to describe the URI substring
    # matched by the parser to one of these rules.

    # The authority component is preceded by a double slash ("//") and is
    # terminated by the next slash ("/"), question mark ("?"), or number
    # sign ("#") character, or by the end of the URI.

    if ( ( my $authority_idx = index $uri, q[//] ) != -1 ) {
        $args{has_authority} = 1;

        if ( ( my $slash_idx = index $uri, q[/], $authority_idx + 2 ) != -1 ) {
            $args{authority} = substr $uri, $authority_idx, $slash_idx - $authority_idx, q[];
        }
        else {
            $args{authority} = substr $uri, $authority_idx, length $uri, q[];
        }

        # remove "//" from authority
        substr $args{authority}, 0, 2, q[];
    }

    $args{path} = $uri;

    # A path segment that contains a colon character (e.g., "this:that")
    # cannot be used as the first segment of a relative-path reference, as
    # it would be mistaken for a scheme name.  Such a segment must be
    # preceded by a dot-segment (e.g., "./this:that") to make a relative-
    # path reference.

    if ( ( my $colon_idx = index $args{path}, q[:] ) != -1 ) {
        my $slash_idx = index $args{path}, q[/];

        if ( $slash_idx == -1 or $colon_idx < $slash_idx ) {
            $args{scheme} = lc substr $args{path}, 0, $colon_idx + 1, q[];

            # remove ":" from scheme
            substr $args{scheme}, -1, 1, q[];
        }
    }

    return \%args;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::URI::Builder

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
