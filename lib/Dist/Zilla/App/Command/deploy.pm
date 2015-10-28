package Dist::Zilla::App::Command::deploy;

use strict;
use warnings;
use utf8;
use Dist::Zilla::App qw[-command];
use Config qw[];

sub abstract {
    my ($self) = @_;

    return 'deploy distribution locally (Pcore)';
}

sub opt_spec {
    my ( $self, $app ) = @_;

    return return
      [ install    => 'install to PATH and PERL5LIB' ],
      [ develop    => 'cpanm --with-develop' ],
      [ recommends => 'cpanm --with-recommends' ],
      [ suggests   => 'cpanm --with-suggests' ];
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    # NOTE args is just raw array or params, that not described as options

    die 'no args expected' if @{$args};

    return;
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    if ( !$INC{'Pcore.pm'} ) {
        print qq[Pcore is required to run this command\n];

        return;
    }

    # chmod
    $self->_chmod;

    # cpanm
    exit 100 if !$self->_cpanm($opt);

    # install
    exit 101 if $opt->install && !$self->_install;

    return;
}

sub _chmod {
    my ($self) = @_;

    print 'chmod ... ';

    if ( $^O !~ /MSWin/sm ) {
        Pcore->file->find(
            {   wanted => sub {
                    if (-d) {
                        Pcore->file->chmod( 'rwx------', $_ ) or print qq[$!: $_\n];
                    }
                    else {
                        if ( $self->_is_exec($_) ) {
                            Pcore->file->chmod( 'r-x------', $_ ) or print qq[$!: $_\n];
                        }
                        else {
                            Pcore->file->chmod( 'rw-------', $_ ) or print qq[$!: $_\n];
                        }
                    }

                    chown $>, $), $_ or print qq[$!: $_\n];    # EUID, EGID
                },
                no_chdir => 1,
            },
            q[.]
        );
    }

    print qq[done\n];

    return;
}

sub _is_exec {
    my ( $self, $path ) = @_;

    $path = Pcore->path($path);

    if ( ( $path->dirname eq 'bin/' || $path->dirname eq 'script/' ) && !$path->suffix ) {
        return 1;
    }
    elsif ( $path->suffix eq 'sh' || $path->suffix eq 'pl' || $path->suffix eq 't' ) {
        return 1;
    }

    return;
}

sub _cpanm {
    my ( $self, $opt ) = @_;

    if ( -f 'cpanfile' ) {
        my $cfg = Pcore->cfg->load( $Pcore::P->{SHARE_DIR} . 'pcore.perl' );

        # install known platform exceptions without tests
        if ( exists $cfg->{cpanm}->{ $Config::Config{archname} } && @{ $cfg->{cpanm}->{ $Config::Config{archname} } } ) {
            Pcore->sys->system( 'cpanm', '--notest', @{ $cfg->{cpanm}->{ $Config::Config{archname} } } ) or return;
        }

        my @args = (    #
            'cpanm',
            '--with-feature', ( $^O =~ /MSWin/sm ? 'windows' : 'linux' ),
            ( $opt->develop    ? '--with-develop'    : () ),
            ( $opt->recommends ? '--with-recommends' : () ),
            ( $opt->suggests   ? '--with-suggests'   : () ),
            '--cpanfile',    'cpanfile',
            '--installdeps', q[.],
        );

        print join( q[ ], @args ) . qq[\n];

        Pcore->sys->system(@args) or return;
    }

    return 1;
}

sub _install {
    my ($self) = @_;

    if ( !Pcore->pm->is_superuser ) {
        print qq[Root privileges required to deploy pcore at system level.\n];

        return;
    }

    my $canon_dist_root = Pcore->file->cwd->realpath->canonpath;

    my $canon_bin_dir = Pcore->path('./bin/')->realpath->canonpath;

    my $canon_dist_lib_dir = Pcore->path('./../')->realpath->canonpath;

    if ( $^O =~ /MSWin/sm ) {

        # set $ENV{PERL5LIB}
        Pcore->sys->system(qq[setx.exe /M PERL5LIB "$canon_dist_root/lib;"]) or return;

        print qq[%PERL5LIB% updated\n];

        # set $ENV{PCORE_DIST_LIB}
        Pcore->sys->system(qq[setx.exe /M PCORE_DIST_LIB "$canon_dist_lib_dir"]) or return;

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

            Pcore->sys->system(qq[setx.exe /M PATH "$ENV{PATH};"]) or return;

            print qq[%PATH% updated\n];
        }
    }
    else {
        my $data = <<"SH";
export PERL5LIB="$canon_dist_root/lib:\$PERL5LIB"
export PCORE_DIST_LIB="$canon_dist_lib_dir"
export PATH="\$PATH:$canon_bin_dir"
SH

        Pcore->file->write_bin( '/etc/profile.d/pcore.sh', { mode => q[rw-r--r--] }, \$data );
    }

    return 1;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 9                    │ NamingConventions::ProhibitAmbiguousNames - Ambiguously named subroutine "abstract"                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 30                   │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 142                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "Dist::Zilla::App::Command::deploy" does not start with a upper    │
## │      │                      │ case letter                                                                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 39, 59, 84, 125,     │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - print                         │
## │      │ 137, 153, 158, 180   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 163                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
