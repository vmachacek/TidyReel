# ADR-004: Android media source strategy for media_kit

- Status: accepted
- Date: 2026-10-07
- Decision owners: TidyReel maintainers

## Context

Android SAF returns `content://` document URIs rather than filesystem paths.
The playback source must support MP4 and MKV, seeking, lifecycle transitions,
external subtitles, and sequential sessions without copying complete media
files into application storage. The build specification makes the real-device
source decision a release blocker.

## Decision

Select `directContentUri`. The Android adapter creates a short-lived playback
lease containing a rebuilt SAF document URI. The Flutter `PlaybackEngine`
passes that URI directly to `media_kit`. Closing a session closes its logical
lease, and engine/application teardown closes remaining playback resources.

External SRT files are a deliberate exception to streaming media access: the
matching sidecar is read through a bounded small-file API and attached to the
player from memory.

## Alternatives considered

- Native `ParcelFileDescriptor` lease exposed as `fd://`: not attempted. The
  conditional gate did not open because direct content-URI playback passed.
  It remains the first fallback if a future supported provider fails for a
  source-opening reason.
- Tokenized loopback HTTP range proxy: not attempted. It has more lifecycle,
  security, networking-permission, and byte-range complexity and is reserved
  for a demonstrated failure of both direct URI and descriptor strategies.
- Full-file cache copy: rejected. It duplicates potentially large private
  media and violates the spike constraints.
- Filesystem path extraction: rejected. SAF does not promise a usable path.

## Consequences

- The production manifest needs no Internet or broad storage/media permission.
- Playback stays streaming and local, with no complete-media cache.
- The selected approach has the smallest bridge and cleanup surface.
- Provider compatibility beyond the tested Android document provider remains
  an empirical compatibility concern.
- Source-opening failures and unsupported codec failures remain distinct; a
  decoder failure must not trigger a source-strategy fallback.

## Validation / reversal criteria

On a Samsung SM-T500 running Android 12, direct URIs successfully played an
H.264/AAC MP4 and a nested H.265/AAC MKV with rendered audio/video, seeks in
both directions, pause/resume, background/foreground cleanup, SRT rendering,
and three sequential sessions. Sanitized logs contained no fatal, access, or
descriptor error markers.

Reopen this decision if a representative supported SAF provider consistently
fails to open or seek a direct URI while the same codec is otherwise supported.
In that case, execute and validate the descriptor strategy before considering
the loopback range proxy. A codec/decoder limitation alone is not reversal
evidence.

## References

- [Milestone 0 Android device validation](../manual-tests/milestone-0-android.md)
- [media_kit package](https://pub.dev/packages/media_kit)
- [Milestone 0 risk-spike design](../superpowers/specs/2026-10-07-milestone-0-android-risk-spike-design.md)
