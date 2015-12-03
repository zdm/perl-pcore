package Pcore::Util::Term;

use Pcore;
use Term::ReadKey qw[];

no Pcore;

sub width ($self) {
    state $required = do {
        require Term::Size::Any;

        Term::Size::Any::_require_any();

        1;
    };

    return scalar Term::Size::Any::chars();
}

sub pause ( $self, @ ) {
    my %args = (
        msg     => 'Press any key to continue...',
        timeout => 0,
        @_[ 1 .. $#_ ],
    );

    print $args{msg};

    Term::ReadKey::ReadMode(3);

    Term::ReadKey::ReadKey( $args{timeout}, $STDIN );

    Term::ReadKey::ReadMode(0);

    print $LF;

    return;
}

sub prompt ( $self, $msg, $opt, @ ) {
    my %args = (
        default => undef,
        line    => 0,
        echo    => 1,
        timeout => 0,       # timeout, after the default value will be accepted
        @_[ 3 .. $#_ ],
    );

    die qq[Invalid default value] if defined $args{default} && !( $args{default} ~~ $opt );

    $args{default} = $opt->[0] if $args{timeout} && !defined $args{default};

    print $msg, ' (', join( q[|], $opt->@* ), ')';

    print " [$args{default}]" if defined $args{default};

    print ': ';

  READ:
    my @possible = ();

    my $input = $self->read_input(
        line       => $args{line},
        edit       => 1,
        echo       => $args{echo},
        echo_char  => undef,
        timeout    => $args{timeout},
        clear_echo => 1,
        on_read    => sub ($input) {
            @possible = ();

            for my $val ( $opt->@* ) {
                push @possible, $val if !index $val, $input, 0;
            }

            if ( !@possible ) {
                return 0;    # do not accept char / line, clear echo, continue
            }
            elsif ( @possible > 1 ) {
                return 1;    # for char mode only, accept char and continue reading
            }
            else {
                return;      # accept / line and exit
            }
        }
    );

    if ( !defined $input ) {    # timeout, no user input
        if ( defined $args{default} ) {
            $possible[0] = $args{default};
        }
        else {
            goto READ;
        }
    }

    print $possible[0];

    print $LF;

    return $possible[0];
}

sub read_password ( $self, @ ) {
    my %args = (
        msg       => 'Enter password',
        echo      => 1,
        echo_char => q[*],
        @_[ 1 .. $#_ ],
    );

    print $args{msg}, ': ';

    my $input = $self->read_input(
        line      => 1,
        edit      => 1,
        echo      => $args{echo},
        echo_char => $args{echo_char},
    );

    print $LF;

    return $input;
}

# NOTE on_read callback should return:
# line mode:
#     - undef  - accept line and return;
#     - !undef - do not accept line, clear echo, continue reading;
# char mode:
#  - undef - accept last char and return;
#  - 0     - do not accept last char, continue reading;
#  - 1     - accept last char, continue reading;
sub read_input ( $self, @ ) {
    my %args = (
        line       => 1,
        edit       => 1,
        echo       => 1,
        echo_char  => undef,
        timeout    => 0,
        clear_echo => 0,       # clear echo on return
        on_read    => undef,
        @_[ 1 .. $#_ ],
    );

    Term::ReadKey::ReadMode(3);

    my $input = q[];

    my $add_char = sub ($char) {
        print $args{echo_char} // $char if $args{echo};

        $input .= $char;

        return;
    };

    my $delete_char = sub {
        if ( length $input ) {
            print "\e[1D\e[K" if $args{echo};

            substr $input, -1, 1, q[];
        }

        return;
    };

    my $clear_echo = sub {
        if ( $args{echo} && defined $input && ( my $len = length $input ) ) {
            print "\e[${len}D\e[K";
        }

        return;
    };

    my $clear_input = sub {
        $clear_echo->();

        $input = q[];

        return;
    };

  READ:
    my $key = Term::ReadKey::ReadKey( $args{timeout}, $STDIN );

    if ( !defined $key ) {    # timeout
        undef $input;
    }
    else {
        $args{timeout} = 0;    # drop timout if user start enter something

        $key =~ s/\x0D|\x0A//smg;

        if ( $key eq q[] ) {    # ENTER
            if ( $args{line} ) {
                if ( $args{on_read} ) {
                    if ( defined $args{on_read}->($input) ) {
                        $clear_input->();

                        goto READ;
                    }
                }
            }
            else {
                goto READ;
            }
        }
        elsif ( $key =~ /\e/sm ) {    # ESC seq.
            while ( Term::ReadKey::ReadKey( 0, $STDIN ) ne q[~] ) { }    # read and ignore the rest of the ESC seq.

            goto READ;
        }
        elsif ( $key =~ /[[:cntrl:]]/sm ) {                              # control char
            if ( $args{edit} && ord($key) == 8 || ord($key) == 127 ) {    # BACKSPACE, DELETE
                $delete_char->();
            }

            goto READ;
        }
        else {
            # TODO decode to UTF-8 under windows

            if ( $args{line} ) {
                $add_char->($key);

                goto READ;
            }
            elsif ( $args{on_read} ) {
                my $on_read = $args{on_read}->( $input . $key );

                if ( defined $on_read ) {
                    $add_char->($key) if $on_read;    # char is accepted

                    goto READ;
                }
                else {                                # accept char and return
                    $add_char->($key);
                }
            }
            else {
                $add_char->($key);
            }

        }
    }

    $clear_echo->() if $args{clear_echo};

    Term::ReadKey::ReadMode(0);

    return $input;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 12                   │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 49                   │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 134                  │ Subroutines::ProhibitExcessComplexity - Subroutine "read_input" with high complexity score (28)                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 193                  │ RegularExpressions::ProhibitSingleCharAlternation - Use [\x0D\x0A] instead of \x0D|\x0A                        │
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
