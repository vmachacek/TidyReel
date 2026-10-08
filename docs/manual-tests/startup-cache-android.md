# Startup inventory and skeleton validation

Validated on 2026-10-08 with the connected Samsung SM-T500 (Android 12).

- App tests: 326 full-suite cases passed, followed by the final three scroll
  retention and large-text metadata cases. Android app unit tests: 43 passed.
  Workspace analysis reported no issues.
- Installed the debug build over the existing app, preserving settings and
  media-folder access. The first startup wrote the new app-private
  `files/scan_inventory.json` snapshot: 1,148 videos, 54 subtitles, 1,227 total
  discovered entries, and 25 ignored entries.
- Cold-stopped and restarted the app. The completed inventory timestamp stayed
  exactly `2026-10-08T15:35:55.496155Z`, confirming that startup did not replace
  it with another completed scan. The restored Home displayed 15 titles and
  1,148 files, selected artwork, watchlist state, and the Resume action.
- No Flutter or Android runtime errors appeared in the startup error log.
- Built and installed the release APK over the verified debug build, retaining
  its inventory and preferences. The release app cold-launched successfully
  (`am start -W` reported 3,440 ms for the Android activity).
- Widget checks verified unchanged hero, toolbar, sort-control, app-bar, and
  navigation geometry between loading and content at compact and tablet sizes.
  Refresh retains existing titles and scroll position; enlarged text and late
  metadata do not change hero geometry.

After adding, removing, or editing media, use **Rescan library** to replace the
saved inventory. Missing, corrupt, incompatible, or differently scoped cache
data triggers a first scan after folder access is checked. Canceled and failed
refreshes retain the last complete inventory. Automatic file-change detection
and incremental reconciliation remain outside this change.
