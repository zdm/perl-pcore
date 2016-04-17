package Pcore::Dist::CLI::Id;

use Pcore -class, -ansi;

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
            my $tbl = P->text->table(
                {   style   => 'compact',
                    padding => 1,
                    width   => 120,
                    cols    => [
                        name => {
                            title => 'DIST NAME',
                            width => 35,
                            align => -1,
                        },
                        release => {
                            title => "CURRENT\nRELEASE",
                            width => 14,
                            align => 1,
                        },
                        unreleased => {
                            title => "UNRELEASED\nCHANGES",
                            width => 14,
                            align => 1,
                        },
                        commited => {
                            width => 10,
                            align => 0,
                        },
                    ],
                }
            );

            print $tbl->render_header;

            for my $dist ( sort { $a->name cmp $b->name } $dists->@* ) {
                my @row;

                push @row, $dist->name;

                if ( !defined $dist->id->{current_release} ) {
                    push @row, WHITE . ON_RED . ' unreleased ' . RESET;
                }
                else {
                    push @row, $dist->id->{current_release};
                }

                if ( $dist->id->{current_release_distance} ) {
                    push @row, WHITE . ON_RED . sprintf( ' %3s ', $dist->id->{current_release_distance} ) . RESET;
                }
                else {
                    push @row, q[];
                }

                if ( !$dist->is_commited ) {
                    push @row, WHITE . ON_RED . ' no ' . RESET;
                }
                else {
                    push @row, q[];
                }

                print $tbl->render_row( \@row );
            }

            print $tbl->finish;
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
revision: <: $dist.id.node :>
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
## │    2 │ 32                   │ RegularExpressions::ProhibitFixedStringMatches - Use 'eq' or hash instead of fixed-pattern regexps             │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 12                   │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
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
