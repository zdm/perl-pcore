package Pcore::Dist;

use Pcore qw[-class];
use Config qw[];

has root => ( is => 'ro', isa => Maybe [Str], required => 1 );    # absolute path to the dist root
has is_installed => ( is => 'ro', isa => Bool, required => 1 );   # dist is installed as CPAN module, root is undefined
has res_path     => ( is => 'ro', isa => Str,  required => 1 );   # absolute path to the dist share dir
has main_module_path => ( is => 'lazy', isa => Str );             # absolute path

has cfg     => ( is => 'lazy', isa => HashRef, init_arg => undef );
has name    => ( is => 'lazy', isa => Str,     init_arg => undef );    # Dist-Name
has ns      => ( is => 'lazy', isa => Str,     init_arg => undef );    # Dist::Name
has version => ( is => 'lazy', isa => Object,  init_arg => undef );
has scm => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Src::SCM'] ], init_arg => undef );

around new => sub ( $orig, $self, $path ) {
    my $pkg_name;

    if ( $path =~ /[.]pm\z/smo ) {                                     # Package/Name.pm
        $pkg_name = $path;
    }
    elsif ( $path =~ m[[./]]smo ) {                                    # ./path/to/dist
        if ( $path = $self->_find_dist_root($path) ) {
            return $self->$orig(
                {   root         => $path->to_string,
                    is_installed => 0,
                    res_path     => $path . 'share/',
                }
            );
        }
        else {
            return;
        }
    }
    else {    # Package::Name
        $pkg_name = $path =~ s[::][/]smgro . q[.pm];
    }

    my $pkg_path;

    if ( exists $INC{$pkg_name} ) {
        $pkg_path = $INC{$pkg_name};
    }
    else {
        for my $inc (@INC) {
            next if ref $inc;

            if ( -f $inc . q[/] . $pkg_name ) {
                $pkg_path = $inc . q[/] . $pkg_name;

                last;
            }
        }
    }

    if ($pkg_path) {
        my $is_installed = 0;

        # check if package is installed in CPAN location
        for my $cpan_inc ( $self->cpan_path->@* ) {
            if ( index( $pkg_path, $cpan_inc ) == 0 ) {
                $is_installed = 1;

                last;
            }
        }

        if ($is_installed) {
            my $dist_name = $pkg_name =~ s[/][-]smgro;

            substr $dist_name, -3, 3, q[];    # remove ".pm" suffix

            for my $cpan_inc ( $self->cpan_path->@* ) {
                if ( -f $cpan_inc . qq[/auto/share/dist/$dist_name/dist.perl] ) {
                    return $self->$orig(
                        {   root             => undef,
                            is_installed     => 1,
                            res_path         => $cpan_inc . qq[/auto/share/dist/$dist_name/],
                            main_module_path => $pkg_path,
                        }
                    );
                }
            }
        }
        else {
            if ( my $dist_root = $self->_find_dist_root($pkg_path) ) {
                return $self->$orig(
                    {   root         => $dist_root->to_string,
                        is_installed => 0,
                        res_path     => $dist_root . 'share/',
                    }
                );
            }
        }
    }

    return;
};

no Pcore;

# CLASS METHODS
sub global_cfg ($self) {
    state $cfg = do {
        my $_cfg;

        if ( my $home = $ENV{HOME} || $ENV{USERPROFILE} ) {
            $_cfg = P->cfg->load( $home . '/.pcore/config.ini' ) if -f $home . '/.pcore/config.ini';
        }

        $_cfg;
    };

    return $cfg;
}

sub cpan_path ($self) {
    state $cpan_path = do {
        my @cpan_inc;

        my %index;

        for my $var (qw[sitearchexp sitelibexp vendorarchexp vendorlibexp archlibexp privlibexp]) {
            if ( !exists $index{$var} && -d $Config::Config{$var} ) {
                push @cpan_inc, P->path( $Config::Config{$var}, is_dir => 1 )->canonpath;

                $index{$var} = 1;
            }
        }

        \@cpan_inc;
    };

    return $cpan_path;
}

sub _find_dist_root ( $self, $path ) {
    $path = P->path( $path, is_dir => 1 ) if !ref $path;

    if ( !-f $path . 'share/dist.perl' ) {
        $path = $path->parent;

        while ($path) {
            last if -f $path . 'share/dist.perl';

            $path = $path->parent;
        }
    }

    if ( defined $path ) {
        return $path->realpath;
    }
    else {
        return;
    }
}

# BUILDERS
sub _build_cfg ($self) {
    return P->cfg->load( $self->res_path . 'dist.perl' );
}

sub _build_name ($self) {
    return $self->cfg->{dist}->{name};
}

sub _build_ns ($self) {
    return $self->name =~ s/-/::/smgr;
}

sub _build_main_module_path ($self) {
    return $self->root . 'lib/' . $self->ns =~ s[::][/]smgr . '.pm';
}

sub _build_version ($self) {
    my $main_module = P->file->read_bin( $self->main_module_path );

    $main_module->$* =~ m[^\s*package\s+\w[\w\:\']*\s+(v?[\d._]+)\s*;]sm;

    return version->new($1);
}

sub _build_scm ($self) {
    return if $self->is_installed;

    return P->class->load('Pcore::Src::SCM')->new( $self->root );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 49, 75, 109, 141,    │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## │      │ 145                  │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 181                  │ RegularExpressions::ProhibitCaptureWithoutTest - Capture variable used outside conditional                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
