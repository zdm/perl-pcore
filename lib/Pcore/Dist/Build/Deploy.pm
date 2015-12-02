package Pcore::Dist::Buil::Deploy;

use Pcore qw[-class];
use Config qw[];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has install    => ( is => 'ro', isa => Bool, default => 0 );
has develop    => ( is => 'ro', isa => Bool, default => 0 );
has recommends => ( is => 'ro', isa => Bool, default => 0 );
has suggests   => ( is => 'ro', isa => Bool, default => 0 );

no Pcore;

sub run ($self) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    # chmod
    $self->_chmod;

    # cpanm
    exit 100 if !$self->_cpanm;

    # install
    exit 101 if $self->install && !$self->_install;

    return;
}

sub _chmod ($self) {
    print 'chmod ... ';

    if ( !$MSWIN ) {
        P->file->find(
            {   wanted => sub {
                    if (-d) {
                        P->file->chmod( 'rwx------', $_ ) or print qq[$!: $_\n];
                    }
                    else {
                        if ( $self->_is_exec($_) ) {
                            P->file->chmod( 'r-x------', $_ ) or print qq[$!: $_\n];
                        }
                        else {
                            P->file->chmod( 'rw-------', $_ ) or print qq[$!: $_\n];
                        }
                    }

                    chown $>, $), $_ or print qq[$!: $_\n];    # EUID, EGID
                },
                no_chdir => 1,
            },
            q[.]
        );
    }

    say 'done';

    return;
}

sub _is_exec ( $self, $path ) {
    $path = P->path($path);

    if ( ( $path->dirname eq 'bin/' || $path->dirname eq 'script/' ) && !$path->suffix ) {
        return 1;
    }
    elsif ( $path->suffix eq 'sh' || $path->suffix eq 'pl' || $path->suffix eq 't' ) {
        return 1;
    }

    return;
}

sub _cpanm ($self) {
    if ( -f 'cpanfile' ) {
        my $cfg = P->cfg->load( $PROC->res->get( '/data/pcore.perl', lib => 'pcore' ) );

        # install known platform exceptions without tests
        if ( exists $cfg->{cpanm}->{ $Config::Config{archname} } && $cfg->{cpanm}->{ $Config::Config{archname} }->@* ) {
            P->sys->system( 'cpanm', '--notest', $cfg->{cpanm}->{ $Config::Config{archname} }->@* ) or return;
        }

        my @args = (    #
            'cpanm',
            '--with-feature', ( $^O =~ /MSWin/sm ? 'windows' : 'linux' ),
            ( $self->develop    ? '--with-develop'    : () ),
            ( $self->recommends ? '--with-recommends' : () ),
            ( $self->suggests   ? '--with-suggests'   : () ),
            '--cpanfile',    'cpanfile',
            '--installdeps', q[.],
        );

        print join( q[ ], @args ) . qq[\n];

        Pcore->sys->system(@args) or return;
    }

    return 1;
}

sub _install ($self) {
    if ( !P->pm->is_superuser ) {
        print qq[Root privileges required to deploy pcore at system level.\n];

        return;
    }

    my $canon_dist_root = P->file->cwd->realpath->canonpath;

    my $canon_bin_dir = P->path('./bin/')->realpath->canonpath;

    my $canon_dist_lib_dir = P->path('./../')->realpath->canonpath;

    if ($MSWIN) {

        # set $ENV{PERL5LIB}
        P->sys->system(qq[setx.exe /M PERL5LIB "$canon_dist_root/lib;"]) or return;

        print qq[%PERL5LIB% updated\n];

        # set $ENV{PCORE_DIST_LIB}
        P->sys->system(qq[setx.exe /M PCORE_DIST_LIB "$canon_dist_lib_dir"]) or return;

        print qq[%PCORE_DIST_LIB% updated\n];

        # update $ENV{PATH}
        require Win32::TieRegistry;

        my $system_path = Win32::TieRegistry->new('LMachine\SYSTEM\CurrentControlSet\Control\Session Manager\Environment')->GetValue('PATH');

        my $env_path = lc $system_path =~ s[/][\\]smgr;

        $canon_bin_dir =~ s[/][\\]smg;

        my $bin_dir_lc = lc $canon_bin_dir;

        if ( $env_path !~ m[\Q$bin_dir_lc\E(?:/|)(?:;|\Z)]sm ) {    # check if pcore bin dir is already in the path
            my @path = grep { $_ && !/\A\h+\z/sm } split /;/sm, $system_path;    # remove empty path tokens, and tokens, consisting only from spaces

            push @path, $canon_bin_dir;

            $ENV{PATH} = join q[;], @path;                                       ## no critic qw[Variables::RequireLocalizedPunctuationVars]

            P->sys->system(qq[setx.exe /M PATH "$ENV{PATH};"]) or return;

            print qq[%PATH% updated\n];
        }
    }
    else {
        my $data = <<"SH";
export PERL5LIB="$canon_dist_root/lib:\$PERL5LIB"
export PCORE_DIST_LIB="$canon_dist_lib_dir"
export PATH="\$PATH:$canon_bin_dir"
SH

        P->file->write_bin( '/etc/profile.d/pcore.sh', { mode => q[rw-r--r--] }, \$data );
    }

    return 1;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 108                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 129                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 178                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 182 does not match the package declaration      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Deploy - deploy distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
