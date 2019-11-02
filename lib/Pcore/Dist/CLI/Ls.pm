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
                branch => {
                    width => 10,
                    align => 1,
                },
                latest_release => {
                    title => "LATEST\nRELEASE",
                    width => 14,
                    align => 1,
                },
                parent_release => {
                    title => "PARENT\nRELEASE",
                    width => 14,
                    align => 1,
                },
                release_distance => {
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

            # dist name
            push @row, $dist->name;

            my $dist_id = $dist->id;

            # branch
            push @row, $dist_id->{branch} || ' - ';

            # latest release
            my $releases = $dist->git->git_releases;

            if ( !$releases ) {
                push @row, 'ERROR';
            }
            else {
                my $latest_release = $releases->{data}->[-1];

                if ( !defined $latest_release ) {
                    push @row, $WHITE . $ON_RED . ' unreleased ' . $RESET;
                }
                else {
                    push @row, $latest_release;
                }
            }

            # parent release
            push @row, defined $dist_id->{release} ? $dist_id->{release} : $WHITE . $ON_RED . ' unreleased ' . $RESET;

            # parent release distance
            push @row, !$dist_id->{release_distance} ? ' - ' : $WHITE . $ON_RED . sprintf( ' %3s ', $dist_id->{release_distance} ) . $RESET;

            # is dirty
            push @row, !$dist_id->{is_dirty} ? ' - ' : $WHITE . $ON_RED . ' dirty ' . $RESET;

            # is pushed
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
                    push @row, join "\n", @has_not_pushed;
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
