package Pcore::Dist::Builder::Deploy;

use Pcore qw[-class];
use Config qw[];

with qw[Pcore::Dist::Builder];

has install    => ( is => 'ro', isa => Bool, default => 0 );
has develop    => ( is => 'ro', isa => Bool, default => 0 );
has recommends => ( is => 'ro', isa => Bool, default => 0 );
has suggests   => ( is => 'ro', isa => Bool, default => 0 );

no Pcore;

sub cli_opt ($self) {
    return {
        install    => { desc => 'install to PATH and PERL5LIB', },
        develop    => { desc => 'cpanm --with-develop', },
        recommends => { desc => 'cpanm --with-recommends', },
        suggests   => { desc => 'cpanm --with-suggests', },
    };
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new($opt)->run;

    return;
}

sub run ($self) {

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

    say 'done';

    return;
}

sub _is_exec ( $self, $path ) {
    $path = Pcore->path($path);

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
        my $cfg = Pcore->cfg->load( $PROC->res->get( '/static/pcore.perl', lib => 'pcore' ) );

        # install known platform exceptions without tests
        if ( exists $cfg->{cpanm}->{ $Config::Config{archname} } && @{ $cfg->{cpanm}->{ $Config::Config{archname} } } ) {
            Pcore->sys->system( 'cpanm', '--notest', @{ $cfg->{cpanm}->{ $Config::Config{archname} } } ) or return;
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
    if ( !Pcore->pm->is_superuser ) {
        print qq[Root privileges required to deploy pcore at system level.\n];

        return;
    }

    my $canon_dist_root = Pcore->file->cwd->realpath->canonpath;

    my $canon_bin_dir = Pcore->path('./bin/')->realpath->canonpath;

    my $canon_dist_lib_dir = Pcore->path('./../')->realpath->canonpath;

    if ($MSWIN) {

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
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 122                  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 143                  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder::Deploy - deploy distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
