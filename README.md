
## Configuration Settings

* PreviewShareDirectory

  Defaults to `StaticFilePath/support/previews`
* PreviewShareUrl

  Defaults to `StaticWebPath/support/previews/`
* PreviewShareLogPreviews

  Whether or not to log shared previews to the activity log.
  
  Defaults to 1 (on).
  
* PreviewShareSkipPublish

  Whether or not to skip the publishing step of entry saving when the shared preview entry is set to published.  In other words, whether or not to follow the normal flow of publishing for entries or to force the post-preview share redirect to go directly to the entry edit page.
  
  Defaults to 1 (on).

## Tags

None

## UI Changes

* Adds a "Share Preview" button to the live entry preview header.  This action will save the entry being previewed. _(N.B. that means that if the entry being previewed had been changed to published but not saved, it *will* be published if the preview is shared and the PreviewShareSkipPublish setting is turned off)_

  The shared preview will also include any index templates set to be rebuild on entry publish (_i.e._, static).
