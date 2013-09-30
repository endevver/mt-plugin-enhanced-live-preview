
package PreviewShare::CMS;

use strict;
use warnings;

#use MT::Logger::Log4perl qw( get_logger :resurrect l4mtdump );

use File::Spec;

use MT::Util qw( dirify );

sub preview_share {
    my ( $app, @fwd_params ) = @_;
    my $q = $app->can('query') ? $app->query : $app->param;
    ###l4p my $logger = get_logger(); $logger->trace('preview_share');
    ###l4p $logger->debug('fwd_params: ', @fwd_params ? l4mtdump(\@fwd_params) : 'NONE' );

    # we need to:
    # * save the entry
    # (on the off chance that the preview button was hit before save)
    # * make sure we preserve the preview
    # * copy the preview to a given directory (config option?)
    # * present the user with sharing options
    #   - recipients
    #   - message
    #   - preview link (for copy+pasting)

    # preview is removed iff _preview_file parameter exists
    # but we need to keep it in there to clean up the preview
    # from the archives

    # best for saving the entry:
    # forward to save_entry and catch the situation in a callback
    # and forward back to this mode?

    # if no foward params, we're just starting
    if ( !@fwd_params ) {

        # so grab the preview file
        require MT::Session;

        my $preview = $q->param('_preview_file');
        my $tf      = MT::Session->load( { id => $preview, kind => 'TF' } );
        my $file    = $tf->name;

        # copy that sucker!
        my $base_share_dir = $app->config->PreviewShareDirectory
            || File::Spec->catdir( $app->static_file_path, "support",
            "previews" );
        ###l4p $logger->debug("PreviewShareDirectory: $base_share_dir");

        # each entry is getting its own preview directory
        # so we can have multiple files in there
        $base_share_dir = File::Spec->catdir( $base_share_dir, $preview );

        # cache the share directory for the post save template building
        $app->request( 'preview_share_dir', $base_share_dir );

        # make sure the directory exists
        # before copying a file over
        my $fmgr = $app->blog->file_mgr;
        if ( !-d $base_share_dir ) {

            $fmgr->mkpath($base_share_dir)
                or return $app->error(
                "Error creating preview directory ($base_share_dir): "
                    . $fmgr->errstr );
        }
        ###l4p $logger->debug("Entry PreviewShare directory created at $base_share_dir");

        my $ext = $app->blog->file_extension || '';
        $ext = '.' . $ext if $ext ne '';
        my $preview_share_file
            = File::Spec->catfile( $base_share_dir, 'entry' . $ext );

        $fmgr->put( $file, $preview_share_file )
            or return $app->error(
            "Error writing preview file ($preview_share_file): "
                . $fmgr->errstr );
        ###l4p $logger->debug("Entry PreviewShare file created: $preview_share_file");

        # build the url for the preview
        my $base_share_url = $app->config->PreviewShareUrl
            || $app->static_path . "support/previews/";
        $base_share_url .= '/' unless $base_share_url =~ /\/$/;
        $base_share_url .= $preview . '/';

        if ( $base_share_url =~ m!^/! ) {

            # relative path, prepend blog domain
            my ($blog_domain) = $app->blog->archive_url =~ m|(.+://[^/]+)|;
            $base_share_url = $blog_domain . $base_share_url;
        }

        $app->request( 'preview_share_base_url', $base_share_url );
        $base_share_url .= 'entry' . $ext;

        # stash it
        $app->request( 'preview_share_url', $base_share_url );
        ###l4p $logger->debug("Forwarding to Entry PreviewShare URL: $base_share_url");

        # forward to the save
        return $app->forward('save_entry');
    }
    else {
        # should this be a redirect instead of a POST response
        # on the off chance somebody hits refresh and it gets into
        # a funky state?
        # I'm leaning towards yes.  Since I've done just that.

        my $entry = shift @fwd_params;

        # we've been forwarded here
        # so it's time to build the template to pass to the user
        # let's build the index template(s)

        require MT::Template;
        my @tmpls;
        my $p = MT->component('PreviewShare');

        # prefer the configured list of templates
        # otherwise, load up any staticly built .php or .html files
        if (my $tmpl_ids = $p->get_config_value(
                'preview_templates', 'blog:' . $entry->blog_id
            )
            )
        {
            if ( !ref($tmpl_ids) ) {
                @tmpls = (
                    $tmpl_ids =~ /^\d+$/
                    ? MT::Template->lookup($tmpl_ids)
                    : MT::Template->load(
                        {   blog_id    => $entry->blog_id,
                            identifier => $tmpl_ids
                        }
                    )
                );
            }
            else {
                @tmpls = grep {defined} map {
                    my $tmpl_id = $_;
                    my $tmpl;
                    if ( $tmpl_id =~ /^\d+$/ ) {
                        MT::Template->lookup($tmpl_id);
                    }
                    else {
                        MT::Template->load(
                            {   blog_id    => $entry->blog_id,
                                identifier => $tmpl_id
                            }
                        );
                    }
                } @$tmpl_ids;

            }

            $_->build_type(1) foreach @tmpls;
        }
        else {

            @tmpls = MT::Template->load(
                {   blog_id    => $entry->blog_id,
                    type       => 'index',
                    rebuild_me => 1
                }
            );

            # skip non "web" pages (i.e. no CSS, XML, etc.)
            @tmpls = grep { $_->outfile && $_->outfile =~ /\.(php|html)$/i }
                @tmpls;
        }

        ###l4p $logger->debug('We got '.scalar(@tmpls).' @tmpls back' );
        ###l4p my @tcols = grep { ! m/^(id|name|text|linked_file|modified|created)/ } @{ MT::Template->column_names };
        ###l4p foreach my $t ( @tmpls ) {
        ###l4p     $logger->debug( sprintf( 'Template ID %d %s "%s": ', $t->id, $t->identifier, $t->name ),
        ###l4p                     l4mtdump({ map {  $_ => $t->$_ } @tcols }) );
        ###l4p }

        my $base_dir = $app->request('preview_share_dir');
        my $base_url = $app->request('preview_share_base_url');
        my $url      = $app->request('preview_share_url');

        $app->request( 'building_preview_entry', $entry );

        my @preview_tmpls = ();
        push @preview_tmpls, {
            template_id   => 'entry',
            template_name => 'Entry',
            template_url  => $url
        };

        my $timer = $app->get_timer();
        $timer->pause_partial if $timer;

        my $cnt = 0;

        TEMPLATE: foreach my $tmpl (@tmpls) {

            # create a faked finfo
            require MT::FileInfo;
            my $finfo = MT::FileInfo->new;
            $finfo->{from_queue} = 1; # make sure to skip the queue
            $finfo->virtual(0);       # make sure it isn't saved, just in case

            # now to screw with the template object
            # so we can get the output where we want it

            # N.B.: this is assuming that the outfile column
            # is both relative and doesn't climb up the directory tree
            # (e.g., "index.html" instead of "../something/whatever.html")

            my $new_tmpl  = $tmpl->clone;
            my $orig_file = $new_tmpl->outfile;
            $new_tmpl->outfile(
                File::Spec->catfile( $base_dir, $orig_file ) );

            my $tmpl_desc = ($new_tmpl->identifier || $new_tmpl->name)
                  . ':blogID='.$entry->blog_id;

            ###l4p $logger->debug( ++$cnt . ") Now rebuilding $tmpl_desc" );

            unless (
                $app->rebuild_indexes(
                    BlogID   => $entry->blog_id,
                    Template => $new_tmpl,
                    FileInfo => $finfo,
                    # Force    => 1,  
                )
            ) {
                my $msg = "Preview Share: Error publishing " . $tmpl->outfile
                    . ": " . ($app->errstr||$app->publisher->errstr);
                # TODO: do more about catching errors here
                warn $msg;
                $app->log({
                    blog_id  => $entry->blog_id,
                    level    => MT->model('log')->ERROR(),
                    class    => 'preview-share',
                    category => 'rebuild',
                    message  => $msg,
                });
                ###l4p $logger->error($msg);
                $timer && $timer->mark("PreviewShareAborted:$tmpl_desc");
                next TEMPLATE;
            }

            $timer && $timer->mark("PreviewShareRebuilt:$tmpl_desc");
            ###l4p $logger->debug( "Finished rebuilding $tmpl_desc" );

            push( @preview_tmpls, {
                template_id   => $tmpl->id,
                template_url  => $base_url . $orig_file,
                template_name => $tmpl->name
            });
        }

        $timer && $timer->mark('PreviewShareBuildComplete');
        ###l4p $logger->debug('Finished with all that rebuilding!');
        ###l4p $timer && $logger->debug( $timer->dump() );

        # now that we've built the templates,
        # we need to build the list of templates
        my $preview_tmpl   = $app->load_tmpl('share_page.tmpl');
        my $preview_params = { template_loop => [@preview_tmpls], };
        my $preview_html   = $preview_tmpl->output($preview_params);

        # TODO: Make the filename configurable?
        my $preview_index_file
            = File::Spec->catfile( $base_dir, 'shared_preview.html' );

        ###l4p $logger->debug('Creating preview index file '.$preview_index_file);

        my $fmgr = $app->blog->file_mgr;
        $fmgr->put_data( $preview_html, $preview_index_file );

        # nix the redirect from the save
        # since MT defers to that over a defined response page
        my $redirect = delete $app->{redirect};

        if ( $app->config->PreviewShareSkipPublish ) {

            $redirect = $app->uri(
                mode => 'view',
                args => {
                    id            => $entry->id,
                    blog_id       => $entry->blog_id,
                    _type         => 'entry',
                    saved_changes => 1
                }
            );
        ###l4p $logger->debug('PreviewShareSkipPublish '.$app->config->PreviewShareSkipPublish);
        ###l4p $logger->debug('Redirect set to '.$redirect);
        }

        $url =~ s/entry\.html$/shared_preview.html/;
        # The string `ttp:/` seems to be special in that in some environments
        # the unserialization process effectively breaks the session and causes
        # the user to re-login. Just remove the string `http://` because it's
        # simple and complete, and replace it later.
        $url =~ s!http://!!;
        $app->session( 'preview_url',      $url );
        $app->session( 'preview_entry_id', $entry->id );
        $app->session( 'preview_redirect', $redirect );

        ###l4p $logger->info('Leaving method, redirecting to '.$app->uri(mode => 'start_preview_share', args => { blog_id => $app->blog->id }));
        return $app->redirect(
            $app->uri(
                mode => 'start_preview_share',
                args => { blog_id => $app->blog->id }
            )
        );
    }
}

sub start_preview_share {
    my $app      = shift;
    my $entry_id = $app->session('preview_entry_id');

    my $entry = MT->model('entry')->load( $entry_id )
        or return $app->error('The specified entry ID "' . $entry_id
            . '" could not be loaded.');

    my %params;
    # Replace the `http://` that was stripped from the preview_url previously.
    $params{preview_url} = 'http://' . $app->session('preview_url');
    $params{entry_id}    = $entry_id;
    $params{redirect}    = $app->session('preview_redirect');
    $params{entry_title} = $entry->title
        || "Entry ID $entry_id could not be loaded.";
    $params{blog_id} = $entry->blog_id;

    # build the list for the autocomplete
    my $author_complete_options = {};
    $author_complete_options->{status} = MT::Author::ACTIVE()
        unless $app->config->PreviewShareCompleteInactive;
    $params{share_completes} = [
        grep {$_}
            map { ( $_->email, $_->name, $_->nickname ) }
            MT::Author->load($author_complete_options)
    ];

    return $app->load_tmpl( 'share_preview.tmpl', \%params );
}

sub source_preview_strip {
    my ( $cb, $app, $tmpl ) = @_;
    my $q = $app->can('query') ? $app->query : $app->param;

    # Preview Share only works on Entries, so hide it from Pages.
    return if $q->param('_type') eq 'page';

    # Find the "Re-edit this entry" button and append the "Share preview"
    # button.
    # Note that the "Re-edit" button is formatted differently in MT4 and MT5.
    # (The "$" and space before "</button>")
    my $old = q{name\=\"edit\_button\_value\"\$?\>\s*\<\/button\>};

    my $new = qq{<button
                mt:mode="preview_share"
                type="submit"
                name="preview_share"
                value="preview_share"
                title="Share Preview"
                class="action button primary-button"
                >Share Preview</button>};

    $$tmpl =~ s/($old)/$1$new/gsm;
}

sub post_save_entry {
    my ( $cb, $app, $entry, $orig ) = @_;

    if ( $app->request('preview_share_url') ) {

        # this is the post save callback firing
        # after being forwarded to save_entry
        # we should re-forward to the sharing code
        $app->forward( 'preview_share', $entry );
    }

    return 1;
}

sub do_preview_share {
    my $app = shift;
    my $q   = $app->can('query') ? $app->query : $app->param;
    
    my $blog_id = $q->param('blog_id');
    my $blog = MT->model('blog')->load( $blog_id );

    # get the recipient list
    my $share_to = $q->param('share_to');
    my @recipients = split( /\s*,\s*/, $share_to );

    # and the sharing message
    my $share_message = $q->param('share_message');

    # need some error condition checking here
    # what if they're not sharing with anybody?

    my %params;
    my $entry_id    = $app->session('preview_entry_id');
    my $preview_url = $app->session('preview_url');
    my $redirect    = $app->session('preview_redirect');

    # clear out the session, since we're actually sharing the preview now
    $app->session( 'preview_entry_id', '' );
    $app->session( 'preview_url',      '' );
    $app->session( 'preview_redirect', '' );

    # let's build the email

    # - first, load the entry, so we can build he subject
    my $e = MT->model('entry')->load($entry_id);

    # TODO: Make the subject and body more configurable
    my $subject
        = '['
        . $blog->name . '] '
        . $app->user->name
        . ' shared a preview of "'
        . $e->title . '"';

    my $body = <<"EMAIL";
View the preview: $preview_url
EMAIL
    $body .= "\n\n$share_message\n" if $share_message;

RECIPIENT:
    foreach my $recip (@recipients) {
        # it's a name without an @, so not an email
        unless ( $recip =~ /@/ ) {

            # first try name, then nickname
            my $a;
            if ( $a = MT::Author->load( { name => $recip } ) ) {
                next RECIPIENT
                    unless $a->email;
                $recip = $a->email;
            }
            elsif ( $a = MT::Author->load( { nickname => $recip } ) ) {
                next RECIPIENT
                    unless $a->email;
                $recip = $a->email;
            }
            else {
                # couldn't find an author based on name or nickname
                # skip it
                $app->log({
                    blog_id  => $blog->id,
                    level    => MT->model('log')->ERROR(),
                    class    => 'preview-share',
                    category => 'notification',
                    message  => 'Preview Share could not send a preview of '
                        . 'entry #' . $e->id . ' (' . $e->title
                        . ') with user "' . $recip . '" because they could not '
                        . 'be found.',
                });

                next RECIPIENT;
            }
        }

        my %head = ( To => $recip, Subject => $subject );

        # send the preview notification email
        require MT::Mail;
        MT::Mail->send( \%head, $body ) or die MT::Mail->errstr;
    }

    if ( $app->config->PreviewShareLogPreviews ) {
        $app->log({
            blog_id  => $blog->id,
            level    => MT->model('log')->ERROR(),
            class    => 'preview-share',
            category => 'notification',
            message  => $app->user->name . ' shared preview of entry #' . $e->id
                . ' (' . $e->title . ") with $share_to.",
        });
    }

    # Then redirect the user to the original page that they *would* have
    # been sent to.
    return $app->redirect($redirect);
}

sub __hdlr_ca_index_templates {
    my ( $app, $ctx, $field_id, $field, $value ) = @_;

    return "" unless my $blog = $app->blog;

    if ( !ref($value) ) {
        $value = [$value];
    }
    my %checked = map { $_ => 1 } @$value;

    my $out = '';
    require MT::Template;
    my $tmpl_iter = MT::Template->load_iter(
        { type => 'index', blog_id   => $blog->id },
        { sort => 'name',  direction => 'ascend' }
    );

    $out .= '<ul>';
    while ( my $tmpl = $tmpl_iter->() ) {
        my $id = $field_id . '-' . ($tmpl->identifier ? $tmpl->identifier : dirify( $tmpl->name ) );

        $out
            .= qq!<li><input type="checkbox" name="$field_id" id="$id" value="!
            . $tmpl->identifier
            . q!" class="cb"!
            . (
            ( $checked{ $tmpl->id } || $checked{ $tmpl->identifier } )
                ? ' checked="checked"'
                : ''
            )
            . '/> <label for="' . $id . '">'
            . $tmpl->name . '</label></li>';
    }

    $out .= '</ul>';

    return $out;
}

1;
