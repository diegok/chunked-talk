#!/usr/bin/env perl

use Mojolicious::Lite;

my $hn_url = 'https://news.ycombinator.com/';

get '/' => sub { shift->render('home') };

get '/not-chunked' => sub {
  my $c = shift;

  my $tx = $c->ua->get( $hn_url );
  if ( $tx->success ) {
    $c->render( inline => $c->render_to_string('opening') . $c->render_to_string( 'articles', news => _extract_news($tx) ) . $c->render_to_string('closing') );
  }
  else {
    $c->render( inline => $c->render_to_string('opening') . 'FETCH ERROR' . $c->render_to_string('closing') );
  }
};

get '/chunked-sync' => sub {
  my $c = shift;

  $c->write_chunk( $c->render_to_string('opening') => sub {
    my $c = shift;

    my $tx = $c->ua->get( $hn_url );
    if ( $tx->success ) {
      $c->finish( 
          $c->render_to_string( 'articles', news => _extract_news($tx) )->encode('utf8')
        . $c->render_to_string('closing')
      );
    }
    else {
      $c->finish( 'FETCH ERROR' . $c->render_to_string('closing') );
    }
  });
};

get '/chunked-async' => sub {
  my $c = shift;

  Mojo::IOLoop::Delay->new->steps(

    # Send page opening and fetch some news.
    sub {
      my $delay = shift;
      $c->write_chunk( $c->render_to_string('opening') => $delay->begin );
      $c->ua->get( $hn_url => $delay->begin );
    },

  # parse news and render
    sub {
      my ( $delay, $tx ) = ( shift, pop );

      return $c->write_chunk( 'FETCH ERROR' => $delay->begin ) unless $tx->success;

      $c->write_chunk( $c->render_to_string( 'articles', news => _extract_news($tx) )->encode('utf8') => $delay->begin );
    },

    # Send page closing and finish
    sub { $c->finish( $c->render_to_string('closing') ) }

  )->wait;
};

sub _extract_news {
  pop->res->dom->find('td.title a')->map(sub{{ 
    url   => $_[0]->attr('href'),
    title => $_[0]->text
  }});
}

app->start;

__DATA__

@@ opening.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Chunked encoding examples</title>
    <link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css">
  </head>
  <body>
    %= include 'navbar';
    <div class="container" style="padding-top:80px;">
      <div class="row">
        <div class="col-md-3">
          <ul class="nav">
            <li><%= link_to 'Not chunked'     => '/not-chunked' %></li>
            <li><%= link_to 'Chunked (Sync)'  => '/chunked-sync' %></li>
            <li><%= link_to 'Chunked (Async)' => '/chunked-async' %></li>
          </ul>
        </div>
        <div class="col-md-9" role="main">

@@ closing.html.ep
        </div>
      </div>
    </div>
  </body>
</html>

@@ articles.html.ep
<p class="lead">This content comes from fetching hacker news frontpage live during this request-response cycle.</p>
<ul>
% for my $link ( @$news ) {
  <li><%= link_to $link->{title} => $link->{url} %></li>
% }
</ul>

@@ navbar.html.ep
<div class="navbar navbar-inverse navbar-fixed-top" role="navigation">
  <div class="container">
    <div class="navbar-header">
      <a class="navbar-brand" href="/">Chunked Examples</a>
    </div>
  </div>
</div>

@@ home.html.ep
%= include 'opening';
<p class="lead">This little app was made to show-off the usage of chunked-encoding to allow slow pages to show faster to the browser. Please open your developer toolbar and select an example from the left.</p>
%= include 'closing';


