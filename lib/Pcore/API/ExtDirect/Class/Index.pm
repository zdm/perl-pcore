package Pcore::API::Class::Index;

use Pcore -role;

with qw[Pcore::API::Class];

requires qw[_build_navigation];

has navigation => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has routes     => ( is => 'rwp',  isa => HashRef,  init_arg => undef );

our $navigation_defaults = {
    xtype     => 'button',
    scale     => 'small',
    width     => 120,
    iconAlign => 'top',
    margin    => '0 0 0 5',
    handler   => 'onNavigationButtonClick',
    ui        => 'default-toolbar',
};

our $exit_button = {
    xtype      => 'button',
    scale      => 'small',
    iconAlign  => 'top',
    glyph      => 0xf08b,
    text       => 'Выход',
    ui         => 'default-toolbar',
    href       => '/api/signout/?continue=/',
    hrefTarget => '_self',
};

around _build_navigation => sub {
    my $orig = shift;
    my $self = shift;

    my %routes = ();

    my $navigation = $self->$orig;

    for my $fold ( $navigation->@* ) {
        my $items = delete $fold->{items};

        for my $button ( $items->@* ) {
            $button->{ext_class} = $self->ext_class( $button->{ext_class} );

            $routes{ $button->{route} } = $button->{ext_class} if $button->{route};
        }

        $fold->{layout} = 'fit';

        $fold->{items} = {
            xtype    => 'panel',
            layout   => 'auto',
            padding  => '5 0 5 0',
            defaults => $navigation_defaults,
            items    => $items,
        };
    }

    $self->_set_routes( \%routes );

    return $navigation;
};

no Pcore;

# VIEWPORT
sub ext_class_viewport {
    my $self = shift;

    my $navigation = $self->navigation;

    return $self->ext_define(
        'Ext.container.Viewport',
        {   controller => $self->ext_type('Controller'),

            layout => 'border',

            routes => $self->routes,

            items => [
                {   region      => 'west',
                    title       => 'Навигация',
                    width       => 255,
                    split       => $TRUE,
                    collapsible => $TRUE,
                    minWidth    => 255,
                    maxWidth    => 380,
                    layout      => {
                        type  => 'vbox',
                        align => 'stretch',
                    },
                    items => [
                        {   flex   => 1,
                            layout => 'accordion',
                            items  => $navigation,
                        },
                        {   layout => 'fit',
                            items  => $exit_button,
                        },
                    ],
                },
                {   region    => 'center',
                    layout    => 'card',
                    reference => 'cardContainer',
                },
            ],
        },
    );
}

# CONTROLLER
sub ext_class_controller {
    my $self = shift;

    my $class = $self->ext_define(
        'Ext.app.ViewController',
        {   routes => { ':id' => 'showComponent', },

            listen => {
                global => {    #
                    error => 'onGlobalError',
                },
            },

            onGlobalError => $self->js_func(
                ['message'], <<'JS'
                    var options = Ext.apply({}, {
                        html: '<strong><span style="color:#FF0000">' + message + '.</span></strong>'
                    },
                    {
                        title: 'Error',
                        align: 'tr',
                        width: 400,
                        glyph: 0xf071,
                        alwaysOnTop: true
                    });

                    Ext.toast(options);
JS
            ),

            showComponent => $self->js_func(
                ['id'], <<'JS'
                    var ext_class = this.getView().routes[id];

                    if(ext_class){
                        this.onNavigationButtonClick({
                            ext_class: ext_class
                        });
                    }
JS
            ),

            instantinatedClasses => {},

            onNavigationButtonClick => $self->js_func(
                ['button'], <<'JS'
                    var cardLayout = this.lookupReference('cardContainer');

                    var id = this.instantinatedClasses[button.ext_class];

                    if(id){
                        cardLayout.setActiveItem(id);
                    }
                    else{
                        var id = Ext.id();
                        this.instantinatedClasses[button.ext_class] = id;

                        var view = Ext.create(button.ext_class, {
                            itemId: id
                        });

                        if (view) {
                            cardLayout.setActiveItem(view);
                        }
                    }
JS
            ),
        }
    );

    return $class;
}

1;
__END__
=pod

=encoding utf8

=cut
