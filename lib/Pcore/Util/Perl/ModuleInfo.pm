package Pcore::Util::Perl::ModuleInfo;

use Pcore qw[-class];

has path => ( is => 'lazy', isa => Str );    # absolute path to package .pm file

has content => ( is => 'lazy', isa => Maybe [ScalarRef] );

has name => ( is => 'lazy', isa => Maybe [Str] );    # Package::Name
has name_path => ( is => 'lazy', isa => Str );       # Package/Name.pm

has is_crypted => ( is => 'lazy', isa => Bool, init_arg => undef );
has abstract => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has version => ( is => 'lazy', isa => Maybe [ InstanceOf ['version'] ], init_arg => undef );

around new => sub ( $orig, $self, $pkg ) {
    if ( $pkg =~ /[.]p(?:[lm])/sm ) {
        return $self->$orig( { path => "$pkg" } );
    }

    return;
};

no Pcore;

sub _build_name ($self) {
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 53                   │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
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
