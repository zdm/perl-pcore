package Pcore::Util::Perl::Module;

use Pcore qw[-class];
use Config qw[];

has name => ( is => 'lazy', isa => Maybe [Str] );    # Module/Name.pm
has content => ( is => 'lazy', isa => ScalarRef );

has path => ( is => 'lazy', isa => Maybe [Str] );    # /absolute/path/to/lib/Module/Name.pm
has lib  => ( is => 'lazy', isa => Maybe [Str] );    # /absolute/path/to/lib/

has is_installed => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_crypted   => ( is => 'lazy', isa => Bool, init_arg => undef );
has abstract => ( is => 'lazy', isa => Maybe [Str], init_arg => undef );
has version => ( is => 'lazy', isa => Maybe [ InstanceOf ['version'] ], init_arg => undef );
has auto_deps => ( is => 'lazy', isa => Maybe [HashRef], init_arg => undef );

around new => sub ( $orig, $self, $module, @inc ) {
    if ( ref $module eq 'SCALAR' ) {
        return $self->$orig(
            {   name    => undef,
                path    => undef,
                lib     => undef,
                content => $module,
            }
        );
    }
    else {

        # convert Package::Name to Module/Name.pm
        if ( $module !~ /[.]p(?:[lm])/smo ) {
            $module =~ s[::][/]smg;

            $module .= '.pm';
        }

        if ( -f $module ) {
            return $self->$orig( { path => P->path($module)->realpath->to_string } );
        }
        else {

            # try to find module in @INC
            for my $lib ( @inc, @INC ) {
                next if ref $lib;

                return $self->$orig( { lib => P->path( $lib, is_dir => 1 )->realpath->to_string, name => $module } ) if -f "$lib/$module";
            }
        }
    }

    return;
};

no Pcore;

sub _split_path ($self) {
    if ( my $path = $self->path ) {
        for my $lib (@INC) {
            next if ref $lib;

            if ( substr( $path, 0, length $lib ) eq $lib ) {
                my $res;

                $res->{lib} = P->path( $lib, is_dir => 1 )->to_string;

                $res->{name} = substr $path, length $res->{lib};

                return $res;
            }
        }
    }

    return;
}

sub _build_name ($self) {
    if ( my $res = $self->_split_path ) {
        $self->{lib} = $res->{lib};

        return $res->{name};
    }

    return;
}

sub _build_path ($self) {
    return $self->lib . $self->name if $self->lib && $self->name;

    return;
}

sub _build_lib ($self) {
    if ( my $res = $self->_split_path ) {
        $self->{name} = $res->{name};

        return $res->{lib};
    }

    return;
}

sub _build_content ($self) {
    return P->file->read_bin( $self->path ) if $self->path;

    return;
}

sub _build_is_installed ($self) {
    return 0 if !$self->lib;

    return -f $self->lib . '/../share/dist.perl' ? 0 : 1;
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

sub _build_auto_deps ($self) {
    return unless my $name = $self->name;

    $name = P->path($name);

    return if $name->suffix eq 'pl';

    my $auto_path = 'auto/' . $name->dirname . $name->filename_base . q[/];

    my $so_filename = $name->filename_base . q[.] . $Config::Config{dlext};

    my $deps;

    for my $lib ( map { P->path($_)->to_string } $PROC->{INLINE_DIR} . 'lib/', @INC ) {
        if ( -f "$lib/$auto_path" . $so_filename ) {
            $deps->{ $auto_path . $so_filename } = "$lib/$auto_path" . $so_filename;

            # add .ix, .al
            for my $file ( P->file->read_dir("$lib/$auto_path")->@* ) {
                my $suffix = substr $file, -3, 3;

                if ( $suffix eq '.ix' or $suffix eq '.al' ) {
                    $deps->{ $auto_path . $file } = "$lib/$auto_path" . $file;
                }
            }

            last;
        }
    }

    return $deps;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 127                  │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 160                  │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Perl::Module - provides static info about perl module

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
