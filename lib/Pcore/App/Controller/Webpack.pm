package Pcore::App::Controller::Webpack;

use Pcore -role;

with qw[Pcore::App::Controller];

has app_dist => ( required => 1, init_arg => undef );

sub get_nginx_cfg ($self) {
    return <<"TXT";
    # webpack $self->{path}
    location $self->{path} {
        root $self->{app_dist};

        rewrite  ^$self->{path}(.*) \$1 break;
        add_header Cache-Control "public, max-age=30672000";

        location =$self->{path} {
            root $self->{app_dist};

            rewrite  ^$self->{path} /index.html break;
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
        }

        location =$self->{path}/ {
            root $self->{app_dist};

            rewrite  ^$self->{path} /index.html break;
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
        }

        location $self->{path}/index.html {
            root $self->{app_dist};

            rewrite  ^$self->{path}/index.html /index.html break;
            add_header Cache-Control "public, private, must-revalidate, proxy-revalidate";
        }
    }
TXT
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::Webpack

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
