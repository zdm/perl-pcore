package Pcore::API::GitHub;

use Pcore -class, -result;
use Pcore::Util::Scalar qw[is_plain_coderef];

has username => ( is => 'ro', isa => Str, required => 1 );
has token    => ( is => 'ro', isa => Str, required => 1 );

sub BUILDARGS ( $self, $args = undef ) {
    $args->{username} ||= $ENV->user_cfg->{GITHUB}->{username} if $ENV->user_cfg->{GITHUB}->{username};

    $args->{token} ||= $ENV->user_cfg->{GITHUB}->{token} if $ENV->user_cfg->{GITHUB}->{token};

    return $args;
}

sub create_repo ( $self, $repo_id, @args ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $cb = is_plain_coderef $args[-1] ? pop @args : undef;

    my %args = (
        description   => undef,
        homepage      => undef,
        private       => \0,
        has_issues    => \1,
        has_wiki      => \1,
        has_downloads => \1,
        @args
    );

    P->http->post(    #
        'https://api.github.com/user/repos',
        headers => {
            AUTHORIZATION => "token $self->{token}",
            CONTENT_TYPE  => 'application/json',
        },
        body      => P->data->to_json( \%args ),
        on_finish => sub ($res) {
            my $api_res;

            if ( $res->status != 200 ) {
                $api_res = result [ $res->status, $res->reason ];
            }
            else {
                my $json = P->data->from_json( $res->body );

                if ( $json->{error} ) {
                    $api_res = result [ 200, $json->{message} ];
                }
                else {
                    $api_res = result 200;
                }
            }

            $cb->($api_res) if $cb;

            $blocking_cv->send($api_res) if $blocking_cv;

            return;
        },
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 22                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::GitHub

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
