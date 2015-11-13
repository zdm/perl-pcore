package Pcore::Dist;

use Pcore qw[-class -const];
use Config qw[];

has root => ( is => 'ro', isa => Maybe [Str], required => 1 );
has is_installed => ( is => 'ro',   isa => Bool, required => 1 );
has res_path     => ( is => 'lazy', isa => Str,  required => 1 );

has cfg_path => ( is => 'lazy', init_arg => undef );
has cfg => ( is => 'lazy', isa => HashRef, init_arg => undef );

has lib_path => ( is => 'lazy', init_arg => undef );

has scm => ( is => 'lazy', init_arg => undef );
has builder => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist::Builder'], init_arg => undef );

const our $CPAN_INC => do {
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

around new => sub ( $orig, $self, $path ) {
    my $pkg_name;

    if ( $path =~ /[.]pm\z/smo ) {    # Package/Name.pm
        $pkg_name = $path;
    }
    elsif ( $path =~ m[[./]]smo ) {    # ./path/to/dist
        if ( $path = _find_dist_root($path) ) {
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
        for my $cpan_inc ( $CPAN_INC->@* ) {
            if ( index( $pkg_path, $cpan_inc ) == 0 ) {
                $is_installed = 1;

                last;
            }
        }

        if ($is_installed) {
            my $dist_name = $pkg_name =~ s[/][-]smgro;

            substr $dist_name, -3, 3, q[];    # remove ".pm" suffix

            for my $cpan_inc ( $CPAN_INC->@* ) {
                if ( -f $cpan_inc . qq[/auto/share/dist/$dist_name/dist.perl] ) {
                    return $self->$orig(
                        {   root         => undef,
                            is_installed => 1,
                            res_path     => $cpan_inc . qq[/auto/share/dist/$dist_name/],
                        }
                    );
                }
            }
        }
        else {
            if ( my $dist_root = _find_dist_root($pkg_path) ) {
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

sub create ( $self, $namespace ) {
    if ( my $path = P->class->load('Pcore::Dist::Create')->new( { namespace => $namespace } )->create ) {
        return $self->new($path);
    }

    return;
}

sub _find_dist_root ($path) {
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

sub _build_cfg_path ($self) {
    return $self->res_path . q[dist.perl];
}

sub _build_cfg ($self) {
    return P->cfg->load( $self->cfg_path );
}

sub _build_lib_path ($self) {
    return if $self->is_installed;

    return if !-d $self->root . 'lib/';

    return $self->root . 'lib/';
}

sub _build_scm ($self) {
    return if $self->is_installed;

    return P->class->load('Pcore::Src::SCM')->new( $self->root );
}

sub _build_builder ($self) {
    return if $self->is_installed;

    return P->class->load('Pcore::Dist::Builder')->new($self);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 1                    │ Modules::ProhibitExcessMainComplexity - Main code has high complexity score (22)                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 66, 92, 130, 134     │ ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 120                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
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
