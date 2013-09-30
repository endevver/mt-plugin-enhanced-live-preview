# Preview Share plugin for Movable Type

As the name says, the Preview Share plugin for Movable Type allows authors to
share Entry previews with others. When previewing an Entry a new button
labeled "Share Preview" is available -- click it and you'll be given a URL to
share, as well as opportunity to email this URL (and specify a message) to a
list of recipients.

# Prerequisites

* Movable Type 4.x or 5.x
* Sendmail or SMTP Mail must already be configured with Movable Type.

# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install


# Configuration

## Configuration Directives

* PreviewShareDirectory

  Defaults to `StaticFilePath/support/previews`
* PreviewShareUrl

  Defaults to `StaticWebPath/support/previews/`
* PreviewShareLogPreviews

  Whether or not to log shared previews to the activity log.
  
  Defaults to 1 (on).
* PreviewShareSkipPublish

  Whether or not to skip the publishing step of entry saving when the shared
  preview entry is set to published.  In other words, whether or not to follow
  the normal flow of publishing for entries or to force the post-preview share
  redirect to go directly to the entry edit page.
  
  Defaults to 1 (on).

## Blog-Level Settings

Visit a blog and choose Tools > Plugins to find Preview Share, then click
Settings. Select which Index Templates should be included in the previews to be
shared.

# Use

* Adds a "Share Preview" button to the live entry preview header.  This action
  will save the entry being previewed. _(N.B. that means that if the entry
  being previewed had been changed to published but not saved, it *will* be
  published if the preview is shared and the PreviewShareSkipPublish setting is
  turned off)_

  The shared preview will also include any index templates set to be rebuild on
  entry publish (_i.e._, static).

# License

This plugin is licensed under the same terms as Perl itself.

#Copyright

Copyright 2013, Endevver LLC. All rights reserved.
