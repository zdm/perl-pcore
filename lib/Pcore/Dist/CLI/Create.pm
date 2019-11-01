package Pcore::Dist::CLI::Create;

use Pcore -class;
use Pcore::Dist;
use Pcore::API::Git qw[:ALL];

extends qw[Pcore::Core::CLI::Cmd];

# CLI
sub CLI ($self) {
    my $tmpl_cfg = $ENV->{share}->read_cfg('/Pcore/dist-tmpl/cfg.ini');

    return {
        abstract => 'create new distribution',
        name     => 'new',
        opt      => {
            tmpl => {
                desc => "template name:\n" . join( "\n", map {"\t\t$_\t$tmpl_cfg->{$_}->{desc}"} keys $tmpl_cfg->%* ),
                isa  => [ keys $tmpl_cfg->%* ],
                min  => 1,
            },
            hosting => {
                short   => 'H',
                desc    => qq[define hosting for upstream repository. Possible values: "$GIT_UPSTREAM_BITBUCKET", "$GIT_UPSTREAM_GITHUB", "$GIT_UPSTREAM_GITLAB"],
                isa     => [ $GIT_UPSTREAM_BITBUCKET, $GIT_UPSTREAM_GITHUB, $GIT_UPSTREAM_GITLAB ],
                default => $GIT_UPSTREAM_BITBUCKET,
            },
            private => {
                desc    => 'create private upstream repository',
                default => 0,
            },
        },
        arg => [    #
            dist_namespace => { type => 'Str', },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    require Pcore::Dist::Build;

    my $status = Pcore::Dist::Build->new->create( {
        base_path               => $ENV->{START_DIR},
        dist_namespace          => $arg->{dist_namespace},
        tmpl                    => $opt->{tmpl},
        upstream_hosting        => $opt->{hosting},
        is_private              => $opt->{private},
        upstream_repo_namespace => $opt->{namespace},
    } );

    exit 3 if !$status;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Create - create new distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
