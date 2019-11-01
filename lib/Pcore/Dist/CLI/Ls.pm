package Pcore::Dist::CLI::Ls;

use Pcore -class, -ansi;

extends qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return { abstract => 'list installed distributions' };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dists;

    for my $dir ( P->file->read_dir( $ENV{PCORE_LIB}, full_path => 1 )->@* ) {
        if ( my $dist = Pcore::Dist->new($dir) ) {
            push $dists->@*, $dist;
        }
    }

    if ($dists) {
        my $tbl = P->text->table(
            style => 'compact',
            width => 120,
            cols  => [
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
                    width => 12,
                    align => 1,
                },
                is_dirty => {
                    title => 'IS DIRTY',
                    width => 10,
                    align => 1,
                },
                pushed => {
                    width => 14,
                    align => 1,
                },
            ],
        );

        print $tbl->render_header;

        for my $dist ( sort { $a->name cmp $b->name } $dists->@* ) {
            my @row;

            push @row, $dist->name;

            my $dist_id = $dist->id;

            if ( $dist_id->{release} eq 'v0.0.0' ) {
                push @row, $WHITE . $ON_RED . ' unreleased ' . $RESET;
            }
            else {
                push @row, $dist_id->{release};
            }

            if ( $dist_id->{release_distance} ) {
                push @row, $WHITE . $ON_RED . sprintf( ' %3s ', $dist_id->{release_distance} ) . $RESET;
            }
            else {
                push @row, q[ - ];
            }

            if ( $dist_id->{is_dirty} ) {
                push @row, $WHITE . $ON_RED . ' dirty ' . $RESET;
            }
            else {
                push @row, q[ - ];
            }

            my $is_pushed = $dist->git->git_is_pushed;

            if ( !$is_pushed ) {
                push @row, q[ ERROR ];
            }
            else {
                my @has_not_pushed;

                for my $branch ( sort keys $is_pushed->{data}->%* ) {
                    my $ahead = $is_pushed->{data}->{$branch};

                    if ($ahead) {
                        push @has_not_pushed, $WHITE . $ON_RED . $SPACE . "$branch ($ahead)" . $SPACE . $RESET;
                    }
                }

                if (@has_not_pushed) {
                    push @row, join ', ', @has_not_pushed;
                }
                else {
                    push @row, q[ - ];
                }
            }

            print $tbl->render_row( \@row );
        }

        print $tbl->finish;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Ls - list installed distributions

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
