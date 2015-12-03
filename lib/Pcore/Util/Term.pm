package Pcore::Util::Term;

use Pcore;
use Term::ReadKey qw[];
use Term::Size::Any qw[chars];

sub width ($self) {
    my ( $width, $height ) = chars;

    return $width;
}

sub pause ( $self, @ ) {
    my %args = (
        msg     => 'Press any key to continue...',
        timeout => undef,
        @_[ 1 .. $#_ ]
    );

    say $args{msg};

    Term::ReadKey::ReadMode(4);

    my $key;

    if ( $args{timeout} ) {
        $key = Term::ReadKey::ReadKey( $args{timeout} );
    }
    else {
        while ( !defined( $key = Term::ReadKey::ReadKey(60) ) ) { }
    }

    Term::ReadKey::ReadMode(0);

    return $key;
}

sub prompt {
    my $self = shift;

    my ( $message, $answers, %options ) = @_;

  REDO_PROMPT:
    print $message . ' (' . join( q[|], map { ( $options{default} && $_ eq $options{default} ) ? uc $_ : $_ } @{$answers} ) . '):';

    Term::ReadKey::ReadMode(4);
    my $buffer = q[];

  REDO_READKEY:
    my $key;
    while ( !defined( $key = Term::ReadKey::ReadKey(60) ) ) { }

    if ( ord($key) == 13 || ord($key) == 10 ) {
        if ( $options{default} && $buffer eq q[] ) {
            Term::ReadKey::ReadMode(0);
            say $options{default};
            return $options{default};
        }
        elsif ( $buffer eq q[] ) {
            goto REDO_READKEY;
        }
        else {
            my @match = grep {/\A\Q$buffer\E/smi} @{$answers};
            if ( scalar @match == 1 ) {
                Term::ReadKey::ReadMode(0);
                if ( $match[0] =~ /\A$buffer(.*)\z/sm ) {
                    say $1;
                }
                else {
                    say q[];
                }
                return $match[0];
            }
            else {
                my @match1 = grep { $_ eq $buffer } @{$answers};
                if ( scalar @match1 == 1 ) {
                    Term::ReadKey::ReadMode(0);
                    if ( $match1[0] =~ /\A$buffer(.*)\z/sm ) {
                        say $1;
                    }
                    else {
                        say q[];
                    }
                    return $match1[0];
                }
                elsif ( scalar @match1 > 1 ) {
                    goto REDO_READKEY;
                }
                else {
                    goto REDO_READKEY;
                }
            }
        }
    }
    else {
        $buffer .= $key;

        my @match = grep {/\A\Q$buffer\E/smi} @{$answers};
        if ( !scalar @match ) {
            if ( length $buffer == 1 ) {
                $buffer = q[];
                goto REDO_READKEY;
            }
            else {
                say q[];
                goto REDO_PROMPT;
            }
        }
        elsif ( scalar @match == 1 && !$options{confirm} ) {
            print $key if ( $key && ord($key) >= 32 );
            Term::ReadKey::ReadMode(0);
            if ( $match[0] =~ /\A$buffer(.*)\z/sm ) {
                say $1;
            }
            else {
                say q[];
            }
            return $match[0];
        }
        else {
            print $key if ( $key && ord($key) >= 32 );
            goto REDO_READKEY;
        }
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 38                   │ Subroutines::ProhibitExcessComplexity - Subroutine "prompt" with high complexity score (32)                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 14                   │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=head1 NAME

Pcore::Util::Term

=head1 METHODS

=head2 prompt

Prompting for user input and returns received value.

    my $res = Pcore::Util::Prompt::prompt($query, \@answers, %options);

=over

=item * OPTIONS

=over

=item * default - default value, returned if enter pressed with no input;

=item * confirm - if true, user need to confirm input with enter;

=back

=back

=head2 pause

Blocking wait for any key pressed.

    Pcore::Util::Prompt::pause([$message], %options);

=over

=item * OPTIONS

=over

=item * timeout - timeout in seconds;

=back

=back

=cut
