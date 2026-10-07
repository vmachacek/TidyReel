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

Only title searches and release/first-air years are sent to TMDB. Episode requests
use provider identifiers and season numbers. Video contents, storage URIs, and
full paths are excluded from requests.

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
provider aliases, alternate episode orders, and full metadata/artwork enrichment
from the build specification remain pending.
