#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( t/lib lib extlib );

BEGIN {
    $ENV{MT_APP} = 'MT::App::CMS';
}

use MT::Test qw( :app :db :data );

use Test::More tests => 2;

require MT;
MT->config->PreviewShareDirectory('t/site/previews');

require MT::Entry;
my %entry = (
    title     => 'Preview Title',
    author_id => 1,
    blog_id   => 1,
    status    => MT::Entry::HOLD()
);

# need to setup the template and template mapping
require MT::Template;
my $tmpl = MT::Template->new;
$tmpl->name("Individual Entry");
$tmpl->text("<MTEntryTitle>: <MTDate>\n\nIndividual Entry Template!\n");
$tmpl->blog_id(1);
$tmpl->type('individual');
$tmpl->save or die $tmpl->errstr;

require MT::TemplateMap;
my $map = MT::TemplateMap->load(
    { blog_id => 1, archive_type => 'Individual', is_preferred => 1 } );
$map->template_id( $tmpl->id );
$map->save or die $map->errstr;

require MT::Author;
my $a   = MT::Author->load(1);
my $app = _run_app(
    $ENV{MT_APP},
    {   __test_user => $a,
        __mode      => 'preview_entry',
        %entry,
    }
);
like( $app->{__test_output}, qr/mt:mode="preview_share"/,
    "Preview Share button appears in preview page" );

# now we parse out the preview and magic token values
my @vals;
for my $f (qw( magic_token _preview_file )) {
    push @vals,
        ( $app->{__test_output}
            =~ m!<input type="hidden" name="$f" value="([^"]+)"! );
}
my ( $token, $_preview ) = @vals;

out_like(
    $ENV{MT_APP},
    {   __test_user   => $a,
        __mode        => 'preview_share',
        magic_token   => $token,
        _preview_file => $_preview,
        %entry,
    },
    qr!Location: /cgi-bin/mt.cgi\?__mode=start_preview_share&blog_id=1!,
    "Got the correct redirect after clicking the share button"
);

$app = _run_app( $ENV{MT_APP},
    { __test_user => $a, __mode => 'start_preview_share', blog_id => 1 } );

# let's try an existing entry
# has to be published to test the non-publishing bit
my $e = MT::Entry->load( { status => MT::Entry::RELEASE() }, { limit => 1 } );

1;
