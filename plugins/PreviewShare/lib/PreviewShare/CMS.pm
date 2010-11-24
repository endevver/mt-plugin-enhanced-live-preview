
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

        # make sure the directory exists
        # before copying a file over
        my $fmgr = $app->blog->file_mgr;
        $fmgr->mkpath($base_share_dir) if !-d $base_share_dir;

        my $ext = $app->blog->file_extension || '';
        $ext = '.' . $ext if $ext ne '';
        my $preview_share_file
            = File::Spec->catfile( $base_share_dir, $preview . $ext );

        $fmgr->put( $file, $preview_share_file )
            or return $app->error(
            "Error writing preview file: " . $fmgr->errstr );

        # build the url for the preview

        my $base_share_url = $app->config->PreviewShareUrl ||
            $app->static_path . "support/previews/"; 
        $base_share_url .= '/' unless $base_share_url =~ /\/$/;
        $base_share_url .= $preview . $ext;

	if ($base_share_url =~ m!^/!) {
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
        my $url  = $app->request('preview_share_url');

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
        = '[' . $e->blog->name . '] ' . $app->user->name . ' shared a preview of "' . $e->title . '"';

    my %head = ( To => \@recipients, Subject => $subject );
    my $body = <<"EMAIL";
View the preview: $preview_url
EMAIL

    $body .= "\n\n$share_message\n" if $share_message;

    # send the preview notification email

    require MT::Mail;
    MT::Mail->send( \%head, $body ) or die MT::Mail->errstr;

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

1;
