# Startup inventory, skeleton, and background refresh validation

Validated on 2026-10-08 with the connected Samsung SM-T500 (Android 12).

- App tests: 354 full-suite cases passed. Android app unit tests: 48 passed.
  Workspace analysis reported no issues.
- Installed the debug build over the existing app, preserving settings and
  media-folder access. The first startup wrote the new app-private
  `files/scan_inventory.json` snapshot: 1,148 videos, 54 subtitles, 1,227 total
  discovered entries, and 25 ignored entries.
- The saved inventory restored before a startup refresh was requested. The
  refreshed snapshot completed at `2026-10-08T15:55:40.368484Z`. Cold-stopped and
  restarted the app again: the previous snapshot remained available during
  folder restoration, then its timestamp advanced to
  `2026-10-08T15:56:18.437734Z` without manually requesting a scan. Both snapshots
  contained 1,148 videos, 54 subtitles, 1,227 discovered entries, and 25 ignored
  entries. The restored Home displayed 15 titles and 1,148 files, selected
  artwork, watchlist state, and the Resume action.
- No Flutter or Android runtime errors appeared in the startup error log.
- Built and installed the release APK over the verified debug build, retaining
  its inventory and preferences. The release app cold-launched successfully
  (`am start -W` reported 2,314 ms for the Android activity).
- Widget checks verified unchanged hero, toolbar, sort-control, app-bar, and
  navigation geometry between loading and content at compact and tablet sizes.
  Refresh retains existing titles and scroll position; enlarged text and late
  metadata do not change hero geometry.
- Startup widget checks held the scan open: cached content rendered before
  enumeration began, watchlist actions remained usable, and the refreshed
  inventory replaced the saved one only after completion. Refresh starts once
  per controller launch, including empty saved libraries, and waits for saved
  preferences and initial title grouping.
- Controller and player checks verified that a refresh failure does not
  interrupt healthy playback or autoplay, a successful refresh does not clear
  playback errors, and cancellation, root changes, disposal, and revoked grants
  reject late worker results. Inventory classification runs in an isolate;
  progress updates are bounded at 150 ms in Dart and Android.

After adding, removing, or editing media, the next launch refreshes the library
automatically. Use **Rescan library** to refresh it immediately. Missing,
corrupt, incompatible, or differently scoped cache
data triggers a first scan after folder access is checked. Canceled and failed
refreshes retain the last complete inventory. Live file-change detection
and incremental reconciliation remain outside this change.
