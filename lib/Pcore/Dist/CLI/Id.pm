package Pcore::Dist::CLI::Id;

use Pcore -class;
use Term::ANSIColor qw[:constants];

with qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'show distribution info',
        opt      => {
            pcore => { desc => 'show info about currently used Pcore distribution', },
            all   => { desc => 'show info about all distributions in $PCORE_LIB directory', },
        },
        arg => [
            dist => {
                desc => 'show info about currently used Pcore distribution',
                isa  => 'Str',
                min  => 0,
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    if ( !$opt->{all} ) {
        my $dist;

        if ( $opt->{pcore} ) {
            $dist = $ENV->pcore;
        }
        elsif ( $arg->{dist} ) {
            if ( $arg->{dist} =~ /\APcore\z/smi ) {
                $dist = $ENV->pcore;
            }
            else {
                $dist = Pcore::Dist->new( $arg->{dist} );
            }
        }

        if ($dist) {
            $self->_show_dist_info($dist);
        }
        else {
            $self->new->run;
        }
    }
    else {
        my $dists;

        for my $dir ( P->file->read_dir( $ENV{PCORE_LIB}, full_path => 1 )->@* ) {
            if ( my $dist = Pcore::Dist->new($dir) ) {
                push $dists->@*, $dist;
            }
        }

        if ($dists) {
            say BOLD . WHITE . sprintf( '%-31s%20s%10s%20s', 'DIST NAME', 'RELEASED VERSION', 'COMMITED', 'UNRELEASED CHANGES' ) . RESET;

            for my $dist ( sort { $a->name cmp $b->name } $dists->@* ) {

                # hg log -r . --template "{latesttag('re:^v\d+[.]\d+[.]\d+$') % '{tag}, {distance}'}"
                my $changes_since_last_release = $dist->scm->server->cmd( qw[log -r . --template], q[{latesttag('re:^v\d+[.]\d+[.]\d+$') % '{distance}'}] )->{o}->[0] - 1;

                printf ' %-30s', $dist->name;

                if ( $dist->last_release_version eq 'v0.0.0' ) {
                    print q[ ] x 8 . WHITE . ON_RED . ' unreleased ' . RESET;
                }
                else {
                    printf '%20s', $dist->last_release_version;
                }

                if ( $dist->has_uncommited_changes ) {
                    print q[ ] x 6 . WHITE . ON_RED . ' no ' . RESET;
                }
                else {
                    printf '%10s', q[];
                }

                if ($changes_since_last_release) {
                    say q[ ] x 15 . WHITE . ON_RED . q[ ] . sprintf( '%3s', $changes_since_last_release ) . q[ ] . RESET;
                }
                else {
                    say sprintf '%20s', q[];
                }
            }
        }
    }

    return;
}

sub run ( $self ) {
    $self->_show_dist_info( $self->dist );

    return;
}

sub _show_dist_info ( $self, $dist ) {
    my $tmpl = <<'TMPL';
name: <: $dist.name :>
version: <: $dist.version :>
revision: <: $dist.revision :>
installed: <: $dist.is_installed :>
module_name: <: $dist.module.name :>
root: <: $dist.root :>
share_dir: <: $dist.share_dir :>
lib_dir: <: $dist.module.lib :>
TMPL

    say P->tmpl->render( \$tmpl, { dist => $dist } )->$*;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 33                   │ RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 63                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 13, 63               │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Id - show different distribution info

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
