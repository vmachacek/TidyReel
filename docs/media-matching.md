# Automatic movie and TV organization

Pocket Cinema combines NormieRename's recognition policies with a local Dart
parser and optional TMDB metadata. The policies are ported into the Android app;
it does not require the .NET CLI or its Claude runtime.

The library presents a show, then its seasons, then its locally available episode
files. Movies remain movie titles. Storage identifiers continue to identify
original files for playback, subtitles, and resume history. Files are never
moved, renamed, split, or overwritten.

## Enable online matching

1. Open Library Settings.
2. Obtain an **API Read Access Token** from
   [TMDB account settings](https://www.themoviedb.org/settings/api).
3. Paste it without a `Bearer` prefix and select **Enable TMDB matching**.

The token is encrypted with an Android Keystore key in private preferences,
separate from ordinary catalog preferences and logs. Turning online matching
off clears the credential; cached metadata remains available offline. Live lookup
and the device Keystore round-trip require validation with a user-provided token.

Title searches and release/first-air years are sent to TMDB. Episode requests
use provider identifiers and season numbers; artwork requests use the matched
show identifier. Image previews and selected downloads come from TMDB's image
service. Video contents, storage URIs, and full paths are excluded from requests.

## Refresh TV artwork

1. Open a TV show's details and select **Refresh artwork**.
2. Choose **Poster** or **Backdrop**, then select an image from the gallery to
   compare it with the current artwork.
3. Select **Use selected** to download and save the image, or **Keep current**
   to leave the current artwork in place. **Refresh again** requests a fresh
   list of images from TMDB.

TMDB must be enabled, and the show must have a title match. The picker offers
**Review match** for an unidentified show. Posters and backdrops are chosen
separately and apply across the show's locally available seasons and episodes.
Images are saved in private app storage and remain available offline after a
restart. The media folder and its existing images stay untouched. A download or
save failure retains the previous choice.

## Recognition and review

The parser handles `S01E01`, `1x01`, natural-language markers, chains, bounded
ranges, season-folder inheritance, localized titles, release tags, specials, and
segment letters. Show-folder evidence keeps nested release packs together. Years
distinguish remakes. Arbitrary numbers or resolutions are not episode evidence
outside strong show/season context.

Automatic TMDB title matches require a unique exact normalized primary/original
title and a compatible known year. Confirmed provider identities merge local
aliases. Review Match lists alternatives and allows searching another title.
Manual title selections and local-name preferences survive retries and restarts.

Episode names are added only when numbering and any existing local title agree
with provider evidence. Unique title-only names can identify an episode within a
known season. Segment letters, conflicting names, missing numbers, and unavailable
provider episodes remain visible for review. Combined files retain all episode
references and stay a single playable file. Arbitrary episode assignment and
episode-order correction UI remain pending.

The available 268-file SpongeBob fixture is covered by parser and hierarchy tests:
one show, seasons 1–9, 267 numbered files, 56 combined files, two segment-letter
reviews, and one unresolved special. The full 1,088-file build-spec fixture
baseline and complete Unicode NFKC normalization remain future work.

## Metadata and AI

TMDB is the movie/TV provider. Its API is free for non-commercial use with
attribution; see [TMDB's official FAQ](https://developer.themoviedb.org/docs/faq).
Settings includes its approved logo and required notice in metadata credits.
See [the logo's provenance](tmdb-attribution.md).

This integration makes no LLM calls. NormieRename relied on a Claude prompt and
optional web search without a canonical metadata provider. A future LLM verifier
should choose among bounded real provider candidates and return a validated
selection. It should leave uncertain identity or cartoon episode order for review.

Matching runs in the background. Successful matches and manual choices are cached
in existing native catalog preferences. Provider failures preserve playback;
Settings offers retries. The production Drift database, durable job queue,
provider aliases, alternate episode orders, and full automatic movie/season
metadata and artwork enrichment from the build specification remain pending.
