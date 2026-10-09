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

## Idle refresh policy (2026-10-09)

Cached startup now restores the last complete inventory without enumerating the
media folder. An automatic refresh becomes due six hours after the last
successful scan, including across restarts. Missing or future completion times
are treated as stale. Missing, corrupt, incompatible, or differently scoped
cache data still triggers the first scan immediately after folder access is
checked. **Rescan library**, available in Library Settings and the catalog
toolbar, always bypasses the automatic schedule. The Settings button closes
the sheet and starts a manual scan immediately; it is disabled during a manual
scan and updates when that scan ends.

Automatic scans wait for local preferences and catalog grouping, then a
15-second presentation grace period and five seconds without touch, scrolling,
keyboard events, or text edits. The catalog must be visible, the app resumed,
and the player closed. Activity interrupts automatic work; the last complete
inventory remains available. If provider cancellation takes longer than the
quiet interval, a later maintenance check retries it. Freshness is checked once
a minute during an idle session, and automatic failures back off for 30 minutes
in that session. This is opportunistic maintenance while the app is open;
there is no periodic Android job while the app is closed.

Automatic scans do not publish progress or error banners. Enumeration uses a
dedicated Android thread with background priority, and inventory classification
and cache encoding run in isolates. Equal inventories retain the current entry
list identities while updating the completion time, so an unchanged folder does
not trigger catalog regrouping. Equal cached metadata also avoids unnecessary
regrouping and preference writes. Results are published only after persistence
and a final cancellation/root check, protecting interactions that begin while
the cache write is in flight.

Validation: 397 app tests, 27 package tests, 58 Android unit tests, and
workspace analysis passed. Coverage includes stale/fresh and empty caches,
startup grace, held touch, text input, scrolling cancellation, covered routes,
paused app/player, retry throttling, unchanged/reordered inventory, changed
video/artwork/subtitle details, and cancellation during cache persistence.
Live file-change detection and incremental folder reconciliation remain future
optimizations.
