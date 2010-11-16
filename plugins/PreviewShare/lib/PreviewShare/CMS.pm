
package PreviewShare::CMS;

use strict;
use warnings;

use File::Spec;

sub preview_share {
    my ( $app, $fwd_params ) = @_;

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
   # but we need to keep it in there to clean up the preview from the archives

    # best for saving the entry:
    # forward to save_entry and catch the situation in a callback
    # and forward back to this mode?

    # if no foward params, we're just starting
    if ( !$fwd_params ) {

        # so grab the preview file
        require MT::Session;

        my $preview = $app->param('_preview_file');
        my $tf      = MT::Session->load( { id => $preview, kind => 'TF' } );
        my $file    = $tf->name;

        # copy that sucker!
        my $base_share_dir = $app->config->PreviewShareDirectory;
        my $ext = $app->blog->file_extension || '';
        $ext = '.' . $ext if $ext ne '';
        my $preview_share_file
            = File::Spec->catfile( $base_share_dir, $preview . $ext );

        my $fmgr = $app->blog->file_mgr;
        $fmgr->put( $file, $preview_share_file );

        # build the url for the preview

        my $base_share_url = $app->config->PreviewShareUrl;
        $base_share_url .= '/' unless $base_share_url =~ /\/$/;
        $base_share_url .= $preview . $ext;

        # stash it
        $app->request( 'preview_share_url', $base_share_url );

        # forward to the save
        return $app->forward('save_entry');
    }
    else {

        # we've been forwarded here
        # so it's time to build the template to pass to the user

        # nix the redirect from the save
        # since MT defers to that over a defined response page
        my $redirect = delete $app->{redirect};

        my $file = $app->request('preview_file');
        my $url  = $app->request('preview_share_url');

        my %params;
        $params{preview_file} = $file;
        $params{preview_url}  = $url;
        return $app->load_tmpl( 'share_preview.tmpl', \%params );

    }

    use Data::Dumper;
    my %p = $app->param_hash;
    die Dumper( \%p );
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

1;
