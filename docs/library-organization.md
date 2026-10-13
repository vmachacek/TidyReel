# Rename and organize files

Open **Settings → Rename & organize files** to preview physical changes inside
the selected media folder. Choose **Rename & move** to apply the ready items.
The app rescans afterward and carries saved titles, playback progress, custom
artwork selections, and verified metadata matches across changed storage IDs.

The naming rules follow `C:\dev\NormieRename`, with the requested `TV/` folder:

- Movies: `Movies/Arrival (2016)/Arrival (2016).mkv`
- Single episodes: `TV/Bluey (2018)/Season 01/S01E01 - The Magic Xylophone.mp4`
- Consecutive episodes: `TV/Bluey (2018)/Season 01/S01E01-E03.mp4`
- Separate episodes: `TV/Bluey (2018)/Season 01/S01E01+E03.mp4`
- Subtitles: the video's new basename, preserving suffixes such as `.forced.en.srt`.

Release groups, torrent sites, resolution, and codec clutter are removed.
Explicit editions and meaningful localized titles are preserved. Explicit Czech
and Slovak markers become `[CZ]`, `[SK]`, or `[CZ-SK]` on the title folder.
Containers are preserved and extensions use lowercase.

Movies and series require a verified TMDB match and release/first-air year.
Single episodes also require verified episode metadata that agrees with local
numbering. Explicit multi-episode chains do not need episode-title lookup.
Missing metadata, uncertain numbering, unsafe paths, and duplicate destinations
remain in place with a review explanation. Use **Fix Match** or configure TMDB
in Settings, then open a fresh preview.

The preview enumerates the folder again and pairs `.srt`, `.ass`, `.ssa`, `.vtt`,
`.sub`, `.idx`, and `.nfo` companions by exact video basename, optionally followed
by subtitle language/accessibility suffixes. Other files and artwork remain in
place. A companion is skipped if its associated video cannot be moved.

Android must grant persistent read and write access to the folder. If an existing
grant is read-only, select the same folder again under **Change media folder**.
The operation uses provider-native moves and renames, checks current source
identities and case-insensitive destination collisions, and never overwrites or
deletes media. Providers without native move/rename support report a failure.
Partial provider failures attempt rollback and are shown per file. Scanning and
folder changes pause while the preview is open, and Back is blocked during apply.
Source folders and unrelated torrent files are left in place.

## Android device check

Run `tool/test-library-organization-android.ps1 -DeviceId <adb-serial>` and
select only the numbered `Download/TidyReelOrganizerCheck-...` folder shown by
the runner. It creates tiny text fixtures, opts into the separate
`com.pocketcinema.app.organizercheck` debug package, and uses `--no-uninstall`.
The test refuses storage access in the production package and verifies bytes,
subtitle pairing, episode ranges, existing-destination collisions, and an
unchanged second plan. Successful runs remove only their test package and tree.
Failed runs retain the fixture for diagnosis. Do not run this integration test
directly against the normal Pocket Cinema package: Flutter's integration-test
runner defaults to uninstalling its app at teardown.
