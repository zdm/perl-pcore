package Pcore::Util::Perl::ModuleInfo;

use Pcore qw[-class];

has path => ( is => 'lazy', isa => Str );                   # /absolute/Module/Path.pm
has module_path => ( is => 'lazy', isa => Maybe [Str] );    # Module/Path.pm

has content => ( is => 'lazy', isa => Maybe [ScalarRef] );

# TODO module can provide more, than one package name
has pkg_name => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );    # Package::Name

has is_crypted => ( is => 'lazy', isa => Bool, init_arg => undef );
has abstract => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has version => ( is => 'lazy', isa => Maybe [ InstanceOf ['version'] ], init_arg => undef );

around new => sub ( $orig, $self, $module, @inc ) {
    if ( ref $module eq 'SCALAR' ) {
        return $self->$orig( { content => $module } );
    }
    else {
        my $path;

        if ( $module =~ /[.]p(?:[lm])/sm ) {    # $module has .pl or .pm suffix, this is a module path
            $path = $module;
        }
        else {                                  # Package::Name
            $path = $module =~ s[::][/]smgr . '.pm';
        }

        if ( -f $path ) {
            return $self->$orig( { path => P->path($path)->realpath->to_string } );
        }
        else {
            # try to find in @INC
            for my $lib ( @inc, @INC ) {
                next if ref $lib;

                return $self->$orig( { path => P->path("$lib/$path")->realpath->to_string, module_path => $path } ) if -f "$lib/$path";
            }
        }
    }

    return;
};

no Pcore;

sub _build_module_path ($self) {
    if ( my $path = $self->path ) {
        for my $lib (@INC) {
            next if ref $lib;

            my $lib_path = P->path( $lib, is_dir => 1 );

            if ( ( my $idx = index( $path, $lib, 0 ) ) == 0 ) {
                return substr $path, length $lib_path;
            }
        }
    }

    return;
}

sub _build_pkg_name ($self) {
    if ( $self->content->$* =~ /^\s*package\s+([[:alpha:]][[:alnum:]]*(?:::[[:alnum:]]+)*)/sm ) {
        return $1;
    }

    return;
}

sub _build_content ($self) {
    return P->file->read_bin( $self->path ) if $self->path;

    return;
}

sub _build_is_crypted ($self) {
    return 0 if !$self->content;

    return 1 if $self->content->$* =~ /^use\s+Filter::Crypto::Decrypt;/sm;

    return 0;
}

sub _build_abstract ($self) {
    return if !$self->content;

    return if $self->is_crypted;

    if ( $self->content->$* =~ /=head1\s+NAME\s*[[:alpha:]][[:alnum:]]*(?:::[[:alnum:]]+)*\s*-\s*([^\n]+)/smi ) {
        return $1;
    }

    return;
}

sub _build_version ($self) {
    return if !$self->content;

    return if $self->is_crypted;

    if ( $self->content->$* =~ m[^\s*package\s+\w[\w\:\']*\s+(v?[\d._]+)\s*;]sm ) {
        return version->new($1);
    }

    return;
}

# TODO shuoul return abs_deps_name + lib_related_deps_name
sub get_deps ($self) {

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 92                   │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 56                   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Perl::ModuleInfo - provides static info about perl module

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
