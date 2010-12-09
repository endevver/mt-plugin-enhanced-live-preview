
package PreviewShare::Util;

use strict;
use warnings;

sub build_file_filter {
    my ( $cb, %cb_args ) = @_;

    # kick out unless we're building preview templates
    require MT;
    return 1 unless ( my $entry = MT->request('building_preview_entry') );

    # okay, so we are previewing templates
    # we need to shove the entry into the stash
    my $ctx  = $cb_args{Context};
    my $blog = $cb_args{Blog};

    require MT::Entry;
    my %terms = ( blog_id => $blog->id, status => MT::Entry::RELEASE() );
    my %args = ( sort => 'authored_on', direction => 'descend' );

    if ( my $days = $blog ? $blog->days_on_index : 10 ) {
        my @ago = offset_time_list( time - 3600 * 24 * $days, $blog->id );
        my $ago = sprintf "%04d%02d%02d%02d%02d%02d",
            $ago[5] + 1900, $ago[4] + 1, @ago[ 3, 2, 1, 0 ];
        $terms{authored_on} = [$ago];
        $args{range_incl}{authored_on} = 1;
    }
    elsif ( my $limit = $blog ? $blog->entries_on_index : 10 ) {
        $args{limit} = $limit;
    }

    my @entries = MT::Entry->load( \%terms, \%args );

    # add the previewed entry to the stash iff it isn't already there
    if ( !scalar grep { $_->id == $entry->id } @entries ) {
        push @entries, $entry;

        # resort it into the list
        @entries = sort { $b->authored_on <=> $a->authored_on } @entries;

        # pop off the last one?
        # only if there's a limit on the number of entries
        # what if it's the previewed entry?
        pop @entries if $args{limit};
    }

    $ctx->stash( 'entries', [@entries] );

    return 1;
}

1;
