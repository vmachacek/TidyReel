# ADR-011: Media probing implementation

- Status: accepted
- Date: 2026-10-07
- Decision owners: Pocket Cinema maintainers

## Context

The scanner must display essential local-media facts without decoding the full
file or coupling domain code to Android APIs. The milestone requires duration,
container, video codec, audio codec, and stream count for SAF documents.

## Decision

Probe Android media in the native adapter. Open one read-only
`ParcelFileDescriptor` for the SAF document, then use:

- `MediaMetadataRetriever` for duration, container MIME, dimensions, and
  rotation; and
- `MediaExtractor` for track count plus video/audio track MIME values.

Return a typed, nullable result through the generated platform bridge. Always
release the extractor, retriever, and descriptor in `finally`. Map unavailable,
revoked, unsupported, and generic probe failures to sanitized application
failure codes without exposing URIs or filenames.

## Alternatives considered

- Probe through `media_kit`/libmpv: rejected for this milestone because it
  would bind catalog metadata to the player lifecycle and failure vocabulary.
- Add FFmpeg or a second native metadata library: rejected because Android's
  platform APIs returned every required milestone field on the representative
  files.
- Parse container bytes in Dart: rejected because it expands format and I/O
  complexity and duplicates mature platform behavior.

## Consequences

- Probe behavior is Android-specific behind an app-owned interface.
- Returned values are best-effort and nullable because providers and malformed
  media may omit metadata.
- Codec values are MIME identifiers rather than marketing names.
- Language, channel count, and sample rate are available in the native track
  model but are not yet part of the milestone UI result.
- More detailed metadata or non-Android support can use another adapter without
  changing the domain contract.

## Validation / reversal criteria

The SM-T500 returned all required fields for both representative fixtures:
`video/mp4`, `video/avc`, `audio/mp4a-latm`, and two streams for the MP4; and
`video/x-matroska`, `video/hevc`, `audio/mp4a-latm`, and two streams for the
MKV. Both returned 65-second duration and 640x360 dimensions.

No subtitle track was embedded in these fixtures, so embedded subtitle-track
reporting remains unvalidated. Reverse or supplement this implementation if a
representative supported container repeatedly omits required fields, if probe
cost blocks background scanning, or when desktop adapters need a shared
cross-platform probe backend.

## References

- [Milestone 0 Android device validation](../manual-tests/milestone-0-android.md)
- [MediaMetadataRetriever](https://developer.android.com/reference/android/media/MediaMetadataRetriever)
- [MediaExtractor](https://developer.android.com/reference/android/media/MediaExtractor)
- [Milestone 0 risk-spike design](../superpowers/specs/2026-10-07-milestone-0-android-risk-spike-design.md)
