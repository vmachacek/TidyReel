# Google Play publishing

Status: **Preparation in progress; not ready for public release.** Reviewed
October 8, 2026. Console access, account eligibility, upload signing, privacy
publication, and store submission have not been verified by this document.

## Verified app facts

- Visible name: **Pocket Cinema**. Android package: `com.pocketcinema.app`.
  Current version: `1.0.0+1`; minimum Android version: Android 10 / API 29.
- The pinned Flutter SDK builds with compile/target API 36 (Android 16).
  This meets the [current Play target requirement](https://developer.android.com/google/play/requirements/target-sdk).
- Local MP4/MKV library, SRT subtitles, movie/TV grouping, watchlist, resume,
  episode autoplay, local artwork, and video frame capture are implemented.
- Android's folder picker grants read-only access to the chosen folder. The
  manifest requests no all-files or broad media collection permission.
- Local playback works without an app account. No advertising, billing,
  analytics, crash reporting service, or developer backend was found.
- TMDB matching is optional and requires the user's API Read Access Token.
  The token is encrypted using Android Keystore; disabling online matching
  removes the stored token. Metadata and artwork requests use HTTPS.
- Optional Bluetooth control uses an unpaired broadcast. It can pause enabled
  tablets behind a persistent Loading screen; local recovery is available.

Evidence: [storage decision](adr/003-android-saf-storage-access.md),
[media matching](media-matching.md), [Bluetooth behavior](kill-switch.md),
[dependencies](dependencies.md), and the app source. The repository name
`TidyReel` is not the current user-facing brand.

## Gates before submission

| Item | State / next action |
| --- | --- |
| Play Console account | Signed-in account opens new-account signup; owner selected Personal. Registration, identity/device verification, and production eligibility remain pending. |
| App identity | Owner must confirm Pocket Cinema and `com.pocketcinema.app` before the first upload establishes the package identity. |
| Upload bundle | Build a signed release AAB, preserve the upload key/passwords outside Git, enroll in Play App Signing, and inspect the uploaded artifact. A personal-install APK is not the Play upload artifact. |
| Device checks | Install through the internal testing track and verify folder selection, restart, playback/subtitles, artwork, and optional Bluetooth on real devices. Check the pre-launch report. |
| Native compatibility | Existing release APK passes 16 KB native LOAD alignment and ZIP alignment checks. A real 16 KB device/emulator launch/playback test remains pending; these static checks do not establish full runtime compatibility. See [Android's guide](https://developer.android.com/guide/practices/page-sizes). |
| Publisher/contact | Developer identity, support email, privacy contact, and any website remain **pending owner input**. |
| Privacy policy | Public URL and in-app policy access remain **pending implementation/publication**. Review Android backup/transfer behavior before claiming all saved data stays exclusively on-device. |
| Data safety | Matrix below is a draft; verify third-party retention and all release dependencies before submitting declarations. |
| Audience/availability | Target ages, countries, and free/paid choice remain **pending owner decisions**. Children's media on a test tablet does not determine the target audience. |
| Store assets | Capture actual release UI using owned/licensed demo media. Do not republish the existing cartoon screenshots without rights confirmation. |
| Remote pause | Review the Loading-screen UX, unauthenticated nearby controllers, persistence, recovery discoverability, and two-device behavior before public release. No confirmed policy ruling is asserted here. |
| Native licenses | Audit the exact bundled libmpv/codec components, required notices, and distribution obligations. Package-level MIT entries alone do not establish the licenses of every bundled native component. |
| TMDB use | Confirm permitted use and any commercial license needed for the chosen business model. Current credits include the approved logo and required notice. See [TMDB FAQ](https://developer.themoviedb.org/docs/faq). |

## Build and signing setup

If an app already exists in Play Console, use its existing upload key. Compare
the upload certificate with **App integrity** before uploading; an existing
package cannot be updated with an unrelated new key without an upload-key reset.
For a new app, create an upload key using the JDK's interactive password prompts:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\.android\pocket-cinema-upload.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `apps/pocket_cinema/android/key.properties.example` to `key.properties` in
the same directory and fill in that key's path, alias, and passwords. This file
and keystores are ignored by Git. Use an absolute keystore path with forward
slashes. Back up both the key and credentials securely before first upload.
Do not overwrite an existing key or generate a replacement for an existing app.

From the repository root:

```powershell
.\tool\build-play-bundle.ps1
```

Successful builds are copied with unique names to
`apps/pocket_cinema/build/google-play/` along with a public PEM upload
certificate and SHA-256 checksum. Only the AAB is uploaded as the release.
The script checks signatures and rejects unsigned/debug-signed output. It
temporarily disables personal signing and restores the previous environment.
Run `tool/test-build-play-bundle.ps1` for the build-script checks.

`tool/build-apk.ps1` remains the personal-install path and preserves the
development certificate for tablet updates. Direct release builds require the
upload signing configuration. Never upload bundles signed with a temporary
build-verification key.

## Console sequence

1. Resolve the owner decisions above and complete the account dashboard's
   verification tasks. New personal accounts may require physical-device
   verification through the Play Console mobile app; use a non-rooted Android
   10+ device. Follow the [official device-verification instructions](https://support.google.com/googleplay/android-developer/answer/14316361?hl=en-GB).
2. Create the app with its confirmed name, default language, app type, and
   free/paid choice. Confirm the package before uploading the first bundle.
3. Upload a signed AAB to **Internal testing**, configure trusted testers, and
   install from the opt-in link. Complete the release/device checks above.
4. Complete the main listing, support contact, distribution countries, and
   category (proposed: **Video Players & Editors**). Publish the privacy policy
   and complete App content: ads, app access, content rating, target audience,
   Data safety, and every other declaration shown in this account's dashboard.
   Current inspected implementation supports answering **No** for contains ads.
5. If this is a personal account created after November 13, 2023, run a closed
   test with at least **12 testers opted in continuously for 14 days**, gather
   real feedback, and apply for production access. Internal testing does not
   satisfy that closed-test gate. See [official testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).
6. Fix report/tester findings, finish all gates, increment the version code for
   each replacement upload, then prepare the production release and send it
   for review. Record the final version, signing certificate fingerprints,
   release notes, reviewer instructions, and console outcome.

Account-specific tasks and the console's current warnings take precedence over
assuming eligibility from a locally successful build. See Google's
[review preparation](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en).

## Proposed store listing

Draft only; confirm the brand and release scope first.

**App name:** Pocket Cinema

**Short description (71 characters):**

Organize and play your local movies and TV shows on your Android tablet

**Full description:**

Turn your local video folder into a library that is easy to browse.

Pocket Cinema organizes your movies and TV shows by title, season, and episode,
with a carousel view designed for Android tablets. Choose your media folder,
browse your collection, and pick up where you left off.

- Play local MP4 and MKV videos.
- Use matching SRT subtitle files.
- Browse shows by season and episode.
- Save titles to your watchlist and resume unfinished videos.
- Continue to the next episode automatically.
- Choose local artwork or capture a frame from your video.
- Optionally connect TMDB for title matching, episode names, and artwork.
- Use optional Bluetooth control to pause nearby Pocket Cinema tablets.

Your selected folder is accessed through Android's system picker. Video playback
and local organization work without an account. Online matching is optional and
requires your own TMDB API Read Access Token.

Bring your own video files. Pocket Cinema does not include movies or TV episodes.
Playback depends on the codecs supported by your device.

**Asset preparation:** create a 512 x 512 PNG store icon, a 1024 x 500 feature
graphic, and fresh screenshots of browsing, seasons/episodes, playback, and
settings. Aim for four landscape 1920 x 1080 screenshots for tablet presentation;
capture each declared form factor. Confirm requirements in Google's
[preview-asset guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en-en).

## Privacy and Data safety draft

Google's definition of collection includes transmission to third parties; data
processed only locally is excluded. Optional collection and user-initiated
sharing exceptions have specific conditions. Do not submit a blanket "no data
collected" declaration while optional TMDB is available. Internal-only testing
is exempt from the Data safety section; closed/open/production tracks require
it. See [official Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en-en).

| Data / observed handling | Draft declaration treatment / verification needed |
| --- | --- |
| Video/subtitle contents, folder paths, local artwork/frames, progress, watchlist, inventory, preferences, cached metadata | Processed and retained locally by this app; not transmitted to TMDB. Review Android cloud backup/device transfer separately. |
| Parsed movie/show title and release year sent to TMDB | Proposed **Files and docs** because these describe the user's files; optional, app functionality. Confirm category and provider retention. |
| User-entered alternative-title searches sent to TMDB | Proposed **In-app search history**; optional, app functionality. Confirm provider retention. |
| User-supplied TMDB token sent to TMDB as authorization | Determine whether its association with an identifiable TMDB account requires **User IDs**. Do not treat the encrypted local token as proof no credential data leaves the device. |
| TMDB show/season IDs and image requests | Requests expose requested content and normal network information, including IP address, to TMDB/CDN. Review provider handling; do not infer location collection simply from having an IP address. |
| Bluetooth mode, random session number, revision sent to nearby peers | Plaintext, optional control traffic. Determine whether the temporary session number is a reportable app/device identifier; this is **not a definitive category assignment**. No MAC address/name or location is read by this implementation. |
| Ads, analytics, remote crash logs, payments | No implementation found; recheck the exact release dependency set. |

- **Sharing:** assess the clearly disclosed, user-enabled TMDB flow against the
  user-initiated/consent exception; do not assume TMDB is a contracted service
  provider or claim it never retains requests.
- **Encryption:** TMDB uses HTTPS, but Bluetooth control is plaintext. If its
  traffic is reportable user data, an unconditional "all collected data is
  encrypted in transit" answer is unsupported.
- **Retention/deletion:** document disabling TMDB, releasing folder access,
  clearing Android app storage, local artwork/cache/preferences, and provider
  retention. Clearing app storage does not delete the user's original media.
  Do not offer a developer deletion promise for third-party records without a
  working mechanism. No Pocket Cinema account creation exists.
- **Permissions:** Internet; Bluetooth/Nearby devices; legacy fine-location
  permission on Android 10-11 for BLE discovery only. No location computation
  or location upload was found. Describe these purposes in the policy.

The final privacy policy needs Pocket Cinema/publisher identification, a privacy
contact, all access/use/transfer details above, security, retention/deletion,
and backup behavior. It must be available in-app and at a public, non-geofenced,
non-editable HTML URL. **Publisher, contact, and URL are pending; no policy is
published by this document.** See [Google's User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311).

## Reviewer and tester instructions draft

Complete the missing sample link and test credentials before copying into App
access; keep credentials in the console's private review instructions, not Git.

1. Download the supplied owned/licensed demo files from **[sample download URL
   pending]** into one Android folder. Suggested layout: `Sample Movie
   (2026).mp4`, `Sample Movie (2026).srt`, and `Sample Show/Season 01/Sample Show
   S01E01.mp4` plus `Sample Show S01E02.mp4`. The folder/sample set is not bundled
   or hosted yet.
2. Launch Pocket Cinema, choose that folder in Android's picker, and allow read
   access. Browse the library, play a movie, verify subtitles, pause/seek, resume
   after restarting, and open the show's season and episodes. No app login is
   required for these features.
3. TMDB is optional: open Library Settings, paste **[dedicated reviewer token
   pending]**, enable matching, and test a title with a known TMDB match and its
   artwork. Synthetic demo titles may have no matches; provide an additional
   licensed sample with a known match. Turn off online matching to remove the
   token. Do not require reviewers to obtain their own API credentials.
4. For nearby control, install on two BLE-capable Android devices. On the phone,
   choose **My phone** and **Enable phone control**. On the tablet, choose
   **Tablet** and **Enable nearby control**. Allow permissions and enable
   Bluetooth; Android 10-11 also needs the Location setting on for discovery.
5. Start playback on the tablet, turn **Kill switch mode** on at the phone, and
   confirm Loading with paused audio. Turn it off and confirm playback remains
   paused. If the phone is unavailable, **hold the tablet's Loading spinner for
   five seconds**, then select **Restore tablet**; this disables nearby control.

There is no pairing/private group: any nearby Pocket Cinema controller can affect
enabled instances. Control state can survive a restart or lost contact. Include
these limitations and recovery instructions in the public-release UX review.
