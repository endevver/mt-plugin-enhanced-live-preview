
package PreviewShare::CMS;

use strict;
use warnings;

use File::Spec;

sub preview_share {
    my ( $app, @fwd_params ) = @_;

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

        my $preview = $app->param('_preview_file');
        my $tf      = MT::Session->load( { id => $preview, kind => 'TF' } );
        my $file    = $tf->name;

        # copy that sucker!
        my $base_share_dir = $app->config->PreviewShareDirectory
            || File::Spec->catdir( $app->static_file_path, "support",
            "previews" );

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

        my $ext = $app->blog->file_extension || '';
        $ext = '.' . $ext if $ext ne '';
        my $preview_share_file
            = File::Spec->catfile( $base_share_dir, 'entry' . $ext );

        $fmgr->put( $file, $preview_share_file )
            or return $app->error(
            "Error writing preview file ($preview_share_file): "
                . $fmgr->errstr );

        # build the url for the preview

        my $base_share_url = $app->config->PreviewShareUrl
            || $app->static_path . "support/previews/";
        $base_share_url .= '/' unless $base_share_url =~ /\/$/;
        $base_share_url .= $preview . '/';

        $app->request( 'preview_share_base_url', $base_share_url );
        $base_share_url .= 'entry' . $ext;

        if ( $base_share_url =~ m!^/! ) {

            # relative path, prepend blog domain
            my ($blog_domain) = $app->blog->archive_url =~ m|(.+://[^/]+)|;
            $base_share_url = $blog_domain . $base_share_url;
        }

        # stash it
        $app->request( 'preview_file',      $file );
        $app->request( 'preview_share_url', $base_share_url );

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
                @tmpls = ( MT::Template->load($tmpl_ids) );
            }
            else {
                @tmpls = grep {defined}
                    @{ MT::Template->lookup_multi($tmpl_ids) };
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

        my $base_dir = $app->request('preview_share_dir');
        my $base_url = $app->request('preview_share_base_url');
        my $url      = $app->request('preview_share_url');

        $app->request( 'building_preview_entry', $entry );
        my @preview_tmpls = ();
        push @preview_tmpls,
            {
            template_id   => 'entry',
            template_name => 'Entry',
            template_url  => $url
            };

        foreach my $tmpl (@tmpls) {

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

            $app->rebuild_indexes(
                BlogID   => $entry->blog_id,
                Template => $new_tmpl,
                FileInfo => $finfo,
                Force    => 1,

                )
                or do {
                print STDERR "Error publishing "
                    . $tmpl->outfile . ": "
                    . $app->publisher->errstr
                    . "\n";    # TODO: do more about catching errors here
                next;
                };

            push @preview_tmpls,
                {
                template_id   => $tmpl->id,
                template_url  => $base_url . $orig_file,
                template_name => $tmpl->name
                };
        }

        # now that we've built the templates,
        # we need to build the list of templates
        my $preview_tmpl   = $app->load_tmpl('share_page.tmpl');
        my $preview_params = { template_loop => [@preview_tmpls], };
        my $preview_html   = $preview_tmpl->output($preview_params);

        # TODO: Make the filename configurable?
        my $preview_index_file
            = File::Spec->catfile( $base_dir, 'shared_preview.html' );

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
        }

        my $file = $app->request('preview_file');
        $url =~ s/entry\.html$/shared_preview.html/;
        $app->session( 'preview_entry_id', $entry->id );
        $app->session( 'preview_file',     $file );
        $app->session( 'preview_url',      $url );
        $app->session( 'preview_redirect', $redirect );

        return $app->redirect(
            $app->uri(
                mode => 'start_preview_share',
                args => { blog_id => $app->blog->id }
            )
        );
    }
}

sub start_preview_share {
    my $app = shift;

    my %params;
    $params{entry_id}     = $app->session('preview_entry_id');
    $params{preview_file} = $app->session('preview_file');
    $params{preview_url}  = $app->session('preview_url');
    $params{redirect}     = $app->session('preview_redirect');

    return $app->load_tmpl( 'share_preview.tmpl', \%params );
}

sub source_preview_strip {
    my ( $cb, $app, $tmpl ) = @_;

    my $old = q{name="edit_button_value"$></button>};
    my $new = qq{<button
	        mt:mode="preview_share"
                type="submit"
                name="preview_share"
                value="preview_share"
                title="Share Preview"
                class="primary-button"
                >Share Preview</button>};
    $$tmpl =~ s/\Q$old\E/$old$new/gsm;
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

    # get the recipient list
    my $share_to = $app->param('share_to');
    my @recipients = split( /\s*,\s*/, $share_to );

    # and the sharing message
    my $share_message = $app->param('share_message');

    # need some error condition checking here
    # what if they're not sharing with anybody?

    my %params;
    my $entry_id    = $app->session('preview_entry_id');
    my $preview_url = $app->session('preview_url');
    my $redirect    = $app->session('preview_redirect');

    $params{preview_file} = $app->session('preview_file');

    # clear out the session, since we're actually sharing the preview now
    $app->session( 'preview_entry_id', '' );
    $app->session( 'preview_file',     '' );
    $app->session( 'preview_url',      '' );
    $app->session( 'preview_redirect', '' );

    # let's build the email

    # - first, load the entry, so we can build he subject
    my $e = MT->model('entry')->load($entry_id);

    # TODO: Make the subject and body more configurable
    my $subject
        = '['
        . $e->blog->name . '] '
        . $app->user->name
        . ' shared a preview of "'
        . $e->title . '"';

    my $body = <<"EMAIL";
View the preview: $preview_url
EMAIL
    $body .= "\n\n$share_message\n" if $share_message;

    foreach my $recip (@recipients) {
        my %head = ( To => $recip, Subject => $subject );

        # send the preview notification email

        require MT::Mail;
        MT::Mail->send( \%head, $body ) or die MT::Mail->errstr;
    }

    if ( $app->config->PreviewShareLogPreviews ) {
        $app->log(
            {   message => $app->user->name
                    . 'shared preview of entry #'
                    . $e->id . ' ('
                    . $e->title
                    . ') with '
                    . $share_to,
                class => 'preview-share',
            }
        );
    }

    # the redirect the user to the original page that they *would* have
    # been sent to

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
        $out
            .= qq!<li><input type="checkbox" name="$field_id" value="!
            . $tmpl->id
            . q!" class="cb"!
            . ( $checked{ $tmpl->id } ? ' checked="checked"' : '' ) . '/> '
            . $tmpl->name . '</li>';
    }

    $out .= '</ul>';

    return $out;
}

1;
