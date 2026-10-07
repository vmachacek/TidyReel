# Local Media Hub — Master Implementation Specification for an AI Coding Assistant

> **Document purpose:** This file is the implementation contract for building a Flutter application that provides a Netflix-like catalog and playback experience over user-selected local media files. It is written for an autonomous coding assistant operating directly in the repository.
>
> **Working product name:** `Local Media Hub`
>
> **Primary target:** Android tablets, developed from macOS. The architecture must remain portable to Windows, macOS, and Linux desktop.
>
> **Status:** Build specification, version 1.0, July 2026.

---

<!-- GENERATED_TOC_START -->
## Table of contents

- [0. Instructions to the coding assistant](#section-0)
- [1. Product definition](#section-1)
- [2. Real-library fixture and mandatory edge cases](#section-2)
- [3. Toolchain, IDE, and project initialization](#section-3)
- [4. Architecture](#section-4)
- [5. Domain terminology and entities](#section-5)
- [6. Database design](#section-6)
- [7. Storage abstraction and Android filesystem access](#section-7)
- [8. Scanning and reconciliation](#section-8)
- [9. Filename and folder parser](#section-9)
- [10. Local grouping](#section-10)
- [11. Metadata-provider architecture](#section-11)
- [12. Deterministic matching engine](#section-12)
- [13. LLM verification and prompts](#section-13)
- [14. Media probing and thumbnails](#section-14)
- [15. Playback architecture](#section-15)
- [16. Application services and state management](#section-16)
- [17. Presentation architecture and UX contract](#section-17)
- [18. Navigation and route contract](#section-18)
- [19. Security, credentials, privacy, and data handling](#section-19)
- [20. Logging, observability, and diagnostics](#section-20)
- [21. Testing strategy](#section-21)
- [22. CI, code quality, and release engineering](#section-22)
- [23. Developer workflow and commands](#section-23)
- [24. Architecture decision records](#section-24)
- [25. Delivery plan and milestone acceptance criteria](#section-25)
- [26. Definition of Done](#section-26)
- [27. Release-blocking quality gates](#section-27)
- [28. Backlog beyond MVP](#section-28)
- [29. Implementation status matrix](#section-29)
- [30. Coding-agent execution protocol](#section-30)
- [31. First implementation task for the coding agent](#section-31)
- [32. Authoritative implementation references](#section-32)
- [33. Final product acceptance scenario using the real fixture](#section-33)
- [34. Closing instruction to the coding assistant](#section-34)

<!-- GENERATED_TOC_END -->


<a id="section-0"></a>
## 0. Instructions to the coding assistant

This document is the source of truth for product behavior, architecture, data invariants, implementation sequencing, and quality gates. Read it completely before creating or modifying code.

The application must be implemented incrementally, milestone by milestone. At the start of every milestone:

1. Inspect the current repository and identify what already exists.
2. Compare the repository state with this specification.
3. Write or update `docs/implementation_status.md` with:
   - completed requirements;
   - current milestone;
   - planned changes;
   - known risks;
   - deviations from this document and their rationale.
4. Implement the smallest complete vertical slice satisfying that milestone.
5. Run formatting, static analysis, unit tests, integration tests, and platform builds relevant to the change.
6. Fix all failures introduced by the change before proceeding.
7. Update documentation and commit logically related changes together.

### 0.1 Non-negotiable agent behavior

The coding assistant must:

- Prefer working, tested code over speculative abstractions.
- Preserve the dependency direction defined in this document.
- Never place filesystem, HTTP, database, LLM, or media-player calls directly inside widgets.
- Never trust an LLM response without deterministic validation.
- Never invent a metadata-provider ID.
- Never delete catalog history merely because a drive or folder is temporarily unavailable.
- Never mark files missing after a partial or failed scan.
- Never copy an entire multi-gigabyte video into cache merely to play it, unless the user explicitly chooses that fallback.
- Never log API keys, authorization headers, absolute private paths, raw LLM credentials, or complete LLM prompts containing private filenames.
- Never commit secrets.
- Never leave placeholder production behavior such as `TODO`, `throw UnimplementedError`, mock repositories, hard-coded sample data, or silent exception swallowing in a completed milestone.
- Never change database schema without a migration and migration test after schema version 1 is committed.
- Never use an unmaintained dependency merely because it produces a shorter implementation. Verify maintenance status, supported platforms, licensing, and current API before adding a package.
- Never assume an API example in this document is syntactically current. Verify the current official package documentation before coding while preserving the behavior and contracts specified here.

### 0.2 Permitted deviations

A deviation is acceptable only when all of the following are true:

- Current Flutter, Android, Dart, or package APIs make the specified approach impossible or materially unsafe.
- The replacement preserves the same external behavior and domain invariants.
- The reason is recorded in an Architecture Decision Record under `docs/adr/`.
- Tests prove the replacement behavior.

### 0.3 Definition of “implemented”

A requirement is implemented only when:

- production code exists;
- automated tests cover normal and important failure paths;
- the code is reachable from the actual application;
- errors are surfaced meaningfully;
- the feature works with the supplied real-library fixture;
- static analysis is clean;
- relevant platform builds succeed;
- documentation is updated.

---

<a id="section-1"></a>
## 1. Product definition

### 1.1 Product goal

Build a local-first media application that turns one or more user-selected folders into a polished catalog of movies and television shows. The filesystem must be abstracted away during normal use. The user should see canonical titles, seasons, episodes, artwork, availability, viewing progress, and playback controls rather than release folders and raw filenames.

The application must:

- discover local media without uploading media content;
- reconcile filesystem changes over time;
- identify movies, shows, seasons, episodes, multi-episode files, duplicate releases, localized releases, subtitles, and local artwork;
- obtain canonical metadata from a configured metadata provider;
- use an LLM as a bounded verification and ambiguity-resolution layer;
- retain a complete audit trail of how each match was reached;
- allow the user to repair every incorrect or ambiguous match;
- remember playback position and watched state;
- work offline after metadata has been cached;
- play broad local-media formats through a capable cross-platform player.

### 1.2 Primary user experience

On launch after setup, the user sees:

1. **Continue Watching** — incomplete movies or episodes ordered by most recent playback.
2. **Next Episodes** — the next locally available episodes for shows with viewing history.
3. **Recently Added** — titles receiving newly discovered files.
4. **TV Shows** — canonical show cards.
5. **Movies** — canonical movie cards.
6. **Needs Attention** — unmatched files, ambiguous matches, inaccessible roots, failed probes, and provider errors.

Selecting a movie opens a movie detail page. Selecting a show opens a show detail page with canonical seasons and episodes, including episodes that are known to exist but are not present locally.

### 1.3 Product principles

1. **Canonical catalog, physical assets underneath.** A show, season, episode, movie, and physical file are distinct entities.
2. **Local-first.** Playback and cached catalog browsing must not require internet access.
3. **Filesystem is evidence, not presentation.** Folder placement and filenames inform matching but do not define the UI hierarchy.
4. **Determinism before AI.** Parse and score locally first; use the LLM to verify bounded candidates or resolve ambiguity.
5. **Human correction is first-class.** Every automated decision can be inspected and corrected.
6. **Corrections persist.** Manual decisions create durable rules where appropriate.
7. **No destructive assumptions.** Disconnected storage is not deleted storage.
8. **Auditability.** A user or developer can explain why a file was ignored, grouped, matched, rejected, or selected for playback.
9. **Provider neutrality.** TMDB is the first provider, not the domain model.
10. **Platform isolation.** Android Storage Access Framework details do not leak into domain or UI code.

### 1.4 MVP assumptions

The first production target is an Android tablet with media synchronized into local shared storage, potentially by Syncthing. Development occurs on macOS using Rider and Android tooling.

MVP includes:

- Android 10+ tablets, with the minimum SDK chosen to remain compatible with the actual tablets and current Flutter requirements;
- one local profile, with profile-aware schema from day one;
- multiple library roots;
- Android Storage Access Framework directory access;
- foreground/resumable scanning;
- TMDB metadata adapter;
- optional LLM verification configured by the user;
- movies and episodic TV;
- external SRT subtitles and embedded tracks;
- local playback with `media_kit` or an equivalently capable maintained player;
- portrait and landscape tablet layouts, optimized primarily for landscape;
- offline browsing and playback after initial enrichment.

### 1.5 Explicit non-goals for MVP

Do not implement these until the MVP release gates are met:

- streaming media from a remote server;
- transcoding;
- casting;
- torrent management;
- automatic subtitle downloading;
- cloud account synchronization;
- household profile UI;
- parental controls;
- watch-party features;
- web deployment;
- Apple TV, Android TV, Roku, or game-console targets;
- metadata editing at provider scale;
- automatic filesystem renaming;
- deleting, moving, or modifying user media files;
- background scanning while the app is fully terminated;
- facial recognition or content analysis of video frames;
- recommendation algorithms based on external user tracking.

---

<a id="section-2"></a>
## 2. Real-library fixture and mandatory edge cases

The user supplied a recursive file listing containing 1,168 entries. Treat it as a permanent regression fixture. Copy it into the repository as:

```text
packages/media_parser/test/fixtures/real_library_listing.txt
```

Do not modify the fixture to make tests easier. Add a separate expected-results file when necessary.

### 2.1 Fixture baseline

The scanner/classifier tests must establish these baseline facts:

- Total non-empty listed entries: **1,168**.
- Video-looking entries by extension before artifact filtering: **1,103**.
- macOS AppleDouble/resource-fork entries beginning with `._`: **16** total.
- Resource-fork video entries: **15**.
- Resource-fork subtitle entries: **1**.
- Real video entries after removing resource forks: **1,088**.
- Real SRT subtitle entries after removing resource forks: **54**.
- Remaining non-video/non-subtitle entries include `.txt`, `.jpg`, `.sfv`, and `.gitkeep` files.

The parser should deterministically recognize the season/episode grammar for at least 1,087 of the 1,088 real videos. The remaining filename without an explicit episode number is still groupable and semantically matchable:

```text
Ben and Holly's Little Kingdom ｜ Hard Times ｜ Full Episode Season 2.mp4
```

### 2.2 Mandatory fixture patterns

The implementation must correctly handle all of these real patterns:

#### Standard television pattern

```text
SpongeBob SquarePants S05E01 Friend or Foe.mkv
Bluey S01E01 - The Magic Xylophone.mp4
```

#### Case-insensitive pattern and missing title in filename

```text
S06e01 - Pandi dvojcata.mp4
S07e65 - Plavba domu.mp4
```

The parent folder carries the show identity.

#### `NxNN` pattern

```text
1x07 Maminka pracuje.mkv
2x44 Skříň na hračky.mkv
3x20 Den pro talenty.mkv
```

#### Natural-language season and episode

```text
Ben and Holly’s Little Kingdom ｜ Season 1 ｜ Episode 10｜ Kids Videos.mp4
```

The parser must normalize typographic apostrophes and Unicode separators without destroying the original filename.

#### Chained multi-episode pattern

```text
Octonauts.Above.And.Beyond.S02E07E08.1080p.NF.WEB-DL.DDP5.1.x264-LAZY[eztv.re].mkv
```

This maps one physical file to two canonical episodes.

#### Episode-range pattern

```text
SpongeBob SquarePants (1999) - S01E01-E03 - Help Wanted & Reef Blower & Tea at the Treedome (...).mkv
```

This maps one physical file to three canonical episodes.

#### Episode suffix/part pattern

```text
Spongebob Squarepants S06E11b Spongebob Squarepants vs The Big One.mkv
Spongebob Squarepants S06E26B The Clash of Triton.mkv
```

Do not silently treat `11b` as canonical episode 11. Parse the numeric component and suffix separately, mark the numbering as potentially segmented, and require title/provider evidence.

#### Special pattern

```text
SpongeBob SquarePants Special 5-0 Atlantis Squarepantis.mkv
```

Do not force this into a normal episode without provider evidence.

#### Movie with clean folder/year pattern

```text
Movies/Zootopia (2016) (...)/Zootopia (2016) (...).mkv
```

#### Localized movie title plus release title

```text
Movies/Willy a kouzelná planeta - Astro.Kid.2019.1080p.BluRay.CZ,SK.dabing.mkv
```

The parser should preserve both the localized leading title and likely original release title as title candidates.

#### Movie placed under `TV Shows`

```text
TV Shows/Astro Kid (2019) [...]/Astro.Kid.2019....mp4
TV Shows/The Fixies Top Secret (2017) [...]/The.Fixies.Top.Secret.2017....mp4
TV Shows/The SpongeBob Movie Search For SquarePants (2025) [...]/The.SpongeBob.Movie....mp4
```

Top-level folder name is weak evidence, never authoritative media type.

#### Duplicate/localized releases of one title

```text
Peppa Pig ...
Peppa.Pig.S06.x265 ...
Prasiatko Peppa ...
```

These can resolve to one canonical show while retaining separate physical versions and language metadata.

#### Sidecar subtitles

```text
Bluey S01E01 - The Magic Xylophone.mp4
Bluey S01E01 - The Magic Xylophone.en.srt
```

The subtitle must attach to the video by normalized basename and carry language `en`.

#### macOS resource forks

```text
._S06e48 - Vedecke muzeum.mp4
._Bluey S01E50 - Shaun.en.srt
```

Always classify these as ignored system artifacts. They must never become media, subtitles, duplicates, unresolved items, or scan errors.

#### Non-media sidecars and noise

```text
S01.sfv
www.YTS.MX.jpg
YTSProxies.com.txt
.gitkeep
.stfolder/syncthing-folder-....txt
```

Classify and retain enough audit information to explain why they were ignored, but do not expose them in the normal catalog.

#### Missing episodes

The Ben and Holly fixture has an explicit complete Season 1, while Season 2 is missing numbered episodes 9, 26, and 41 among the numeric filenames and includes one title-only file. The UI and catalog query must be able to show canonical missing episodes independently from local files.

### 2.3 Fixture-based acceptance criteria

After a successful fixture import in test mode:

- no `._` item appears in the catalog or unresolved queue;
- sidecar SRT files are not counted as playable titles;
- movies under `TV Shows` can still become movies;
- all SpongeBob season folders can resolve to one canonical show;
- all Bluey season folders can resolve to one canonical show;
- all Peppa/Prasiatko folders can resolve to one canonical show, subject to user/provider confirmation;
- a physical multi-episode file creates multiple episode links;
- one episode can have multiple physical files;
- no physical file is duplicated merely because it has an external subtitle;
- title cards never expose release-group folder names in normal mode;
- parser test output is deterministic across runs and operating systems.

---

<a id="section-3"></a>
## 3. Toolchain, IDE, and project initialization

### 3.1 IDE

Use **JetBrains Rider** as the primary IDE with current Flutter and Dart plugins. Android Studio may be installed for Android SDK, emulator, profiler, and device tooling, but the repository must not depend on Android Studio-specific project state.

Recommended Rider configuration:

- Flutter SDK path configured explicitly;
- Dart analysis on save;
- format on save for Dart files;
- generated files excluded from manual editing;
- test runner configured for package and workspace tests;
- terminal shell set to the user's normal shell;
- `.idea/` policy decided once and documented; do not commit user-specific paths or secrets.

### 3.2 Toolchain discovery

Before generating the project, record:

```bash
flutter --version
dart --version
flutter doctor -v
java -version
```

Store the non-secret results in `docs/environment.md`.

Use the current Flutter stable channel. Pin the chosen Flutter SDK for reproducibility using the team's selected mechanism, preferably FVM when already available. Do not install global tooling without documenting it.

### 3.3 Repository structure

Use a modular Flutter/Dart workspace:

```text
local_media_hub/
├── README.md
├── LOCAL_MEDIA_HUB_BUILD_SPEC.md
├── analysis_options.yaml
├── pubspec.yaml                         # Workspace/root configuration where supported
├── docs/
│   ├── environment.md
│   ├── implementation_status.md
│   ├── data_model.md
│   ├── matching.md
│   ├── privacy.md
│   └── adr/
├── apps/
│   └── local_media_hub/
│       ├── android/
│       ├── macos/
│       ├── windows/
│       ├── linux/
│       ├── lib/
│       ├── test/
│       ├── integration_test/
│       └── pubspec.yaml
├── packages/
│   ├── media_domain/                   # Pure Dart entities, value objects, repository contracts
│   ├── media_database/                 # Drift schema, DAOs, migrations
│   ├── media_scanner/                  # Scan orchestration and reconciliation
│   ├── media_parser/                   # Pure Dart filename/folder parsing
│   ├── media_metadata/                 # Provider-neutral metadata contracts + TMDB adapter
│   ├── media_matching/                 # Candidate scoring, LLM verification, rules
│   ├── media_playback/                 # Player abstraction, progress semantics
│   ├── media_platform_storage/         # Storage contracts; Android and native adapters
│   ├── media_observability/            # Structured local logging and diagnostics
│   └── media_test_support/              # Fakes, fixtures, builders
├── tool/
│   ├── import_listing.dart
│   ├── parser_report.dart
│   ├── database_inspect.dart
│   └── verify_fixture.dart
└── .github/workflows/                   # Or equivalent CI provider
```

Use Dart pub workspaces if supported by the selected stable SDK. Otherwise use path dependencies and document the fallback. Do not add Melos unless workspace commands are materially inadequate; if added, record the decision in an ADR.

### 3.4 Core dependencies

Resolve current stable compatible versions at implementation time. Prefer `flutter pub add`/`dart pub add` over manually guessing versions. Commit the lockfile for the application.

Expected dependency categories:

- Flutter and Dart SDKs;
- `flutter_riverpod`, Riverpod annotations/generator where code generation is adopted;
- `drift`, `drift_flutter`, `drift_dev`;
- `dio` for HTTP;
- `go_router` for navigation;
- `media_kit`, `media_kit_video`, and the appropriate maintained native video library package;
- `cached_network_image` or an equivalent maintained cache-aware image widget;
- `flutter_secure_storage` for provider and LLM credentials;
- `path`, `path_provider`, `collection`, `crypto`, `uuid`, and `meta` as needed;
- `json_annotation`, `json_serializable` when DTO code generation is useful;
- `freezed` only if it meaningfully reduces safe immutable-state boilerplate; do not introduce it automatically;
- `mocktail` or hand-written fakes for tests;
- `golden_toolkit` only if maintained and compatible; otherwise use Flutter golden APIs directly;
- `integration_test` from Flutter SDK;
- `pigeon` for typed platform-channel contracts where practical.

Do not use the retired original FFmpegKit package. Media probing must be behind an abstraction so the implementation can use native Android media APIs, a maintained FFprobe integration, media-player metadata, or a later replacement without changing the domain.

### 3.5 Static analysis

Start with the current official Flutter lints and strengthen them. At minimum:

- no implicit dynamic in public contracts;
- no ignored futures unless explicitly justified;
- no `print` in production code;
- no use of `BuildContext` across asynchronous gaps;
- exhaustive switches on sealed domain states;
- public APIs documented when behavior is non-obvious;
- generated files excluded from lint noise;
- warnings treated as CI failures.

Create repository-wide commands such as:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Add workspace-aware wrappers under `tool/` or a task runner only when needed.

---

<a id="section-4"></a>
## 4. Architecture

### 4.1 Architectural style

Use a pragmatic layered architecture with strict dependency direction:

```text
Presentation (Flutter widgets, navigation)
             ↓
Application (use cases, coordinators, Riverpod state)
             ↓
Domain (entities, value objects, policies, repository contracts)
             ↑
Infrastructure (Drift, TMDB, LLM, Android SAF, media_kit, caches)
```

Infrastructure implements domain contracts. Domain code must not import Flutter, Drift, Dio, Android classes, media_kit, or provider-specific DTOs.

### 4.2 Major runtime components

```text
┌──────────────────────────────────────────────────────────────────┐
│ Flutter UI                                                       │
│ Home · Search · Movie · Show · Review · Settings · Player       │
└───────────────────────┬──────────────────────────────────────────┘
                        │ commands / reactive queries
┌───────────────────────▼──────────────────────────────────────────┐
│ Application services                                            │
│ LibraryCoordinator · MatchCoordinator · PlaybackCoordinator     │
│ MetadataRefreshCoordinator · JobRunner                           │
└───────────┬───────────────────────┬──────────────────────┬───────┘
            │                       │                      │
┌───────────▼──────────┐  ┌────────▼─────────┐  ┌────────▼────────┐
│ Domain policies       │  │ Repository APIs   │  │ Event/log APIs  │
│ parser/scoring/watch  │  │ catalog/jobs/etc. │  │ diagnostics     │
└───────────┬──────────┘  └────────┬─────────┘  └────────┬────────┘
            │                       │                      │
┌───────────▼───────────────────────▼──────────────────────▼───────┐
│ Infrastructure                                                    │
│ Android SAF · Native FS · Drift/SQLite · TMDB · LLM · media_kit │
└──────────────────────────────────────────────────────────────────┘
```

### 4.3 Required boundaries

Define interfaces for at least:

```dart
abstract interface class LibraryStorageGateway {}
abstract interface class LibraryRepository {}
abstract interface class ScanRepository {}
abstract interface class MediaProbe {}
abstract interface class FilenameParser {}
abstract interface class MetadataProvider {}
abstract interface class LlmMatchVerifier {}
abstract interface class MatchRepository {}
abstract interface class PlaybackEngine {}
abstract interface class PlaybackRepository {}
abstract interface class ArtworkStore {}
abstract interface class SecureCredentialStore {}
abstract interface class AppLogger {}
abstract interface class Clock {}
```

Use a `Clock` abstraction anywhere time affects logic or tests.

### 4.4 Result and failure model

Do not throw infrastructure exceptions through the domain or UI. Convert them into typed failures at boundaries.

Use a sealed result model, for example:

```dart
sealed class AppResult<T> {
  const AppResult();
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);
  final T value;
}

final class FailureResult<T> extends AppResult<T> {
  const FailureResult(this.failure);
  final AppFailure failure;
}
```

Define typed failures including:

- `StoragePermissionFailure`;
- `StorageUnavailableFailure`;
- `ScanCancelledFailure`;
- `DatabaseFailure`;
- `MetadataNetworkFailure`;
- `MetadataRateLimitFailure`;
- `MetadataAuthenticationFailure`;
- `LlmAuthenticationFailure`;
- `LlmSchemaFailure`;
- `LlmPolicyFailure`;
- `PlaybackUnsupportedFailure`;
- `PlaybackSourceFailure`;
- `ProbeFailure`;
- `InvariantViolationFailure`.

Each failure must have:

- stable machine code;
- safe user-facing message key;
- optional technical detail for diagnostics;
- retryability flag;
- causal exception retained only in debug/diagnostic context.

### 4.5 Domain invariants

The following invariants must be enforced in code and, where possible, by database constraints:

1. A physical library file belongs to exactly one library root.
2. A physical video file can link to zero or one canonical title.
3. A physical TV video can link to one or more canonical episodes of that title.
4. A canonical episode can link to zero or many physical files.
5. A movie file must not have episode links.
6. A TV file with episode links must have a title link to the episodes' title.
7. Manual confirmed links are never overwritten automatically.
8. Files are marked missing only after a successful complete scan of an available root.
9. A changed content fingerprint invalidates stale probe and playback assumptions while retaining history for audit.
10. Provider IDs are unique within `(provider, entityType)`.
11. LLM-selected candidate keys must exist in the exact candidate set supplied to that request.
12. User secrets never enter normal application logs.
13. All persisted timestamps are UTC.
14. Playback positions and durations are integer milliseconds.
15. Scan, parse, probe, metadata, match, and artwork states are independently retryable.

---

<a id="section-5"></a>
## 5. Domain terminology and entities

### 5.1 Terminology

- **Library root:** A user-authorized directory tree.
- **Library file:** A physical file discovered under a root, regardless of type.
- **Video asset:** A playable library file classified as video.
- **Sidecar:** A related subtitle, artwork, metadata, checksum, or other file.
- **Canonical title:** A provider-backed movie or TV show.
- **Canonical season:** A provider-backed season or special grouping.
- **Canonical episode:** A provider-backed episode or segment.
- **Title link:** The relationship from a physical video to a canonical title.
- **Episode link:** The many-to-many relationship between physical videos and canonical episodes.
- **Local group:** Files considered likely to describe one title before canonical matching.
- **Match attempt:** An auditable evaluation of candidates.
- **Match rule:** A persisted user-approved rule applied to future scans.
- **Availability:** Whether the physical asset can currently be accessed.
- **Watch state:** User/profile-specific progress independent from metadata availability.

### 5.2 Core enums

Define closed enums or sealed classes equivalent to:

```text
MediaKind: unknown, movie, tv
LibraryFileKind: video, subtitle, artwork, metadata, checksum, text, systemArtifact, ignoredOther
StorageKind: androidSaf, nativePath
RootAvailability: available, permissionRevoked, disconnected, providerUnavailable, scanning, error
ScanMode: initial, startupReconciliation, manualFull, targeted, repair
ScanState: queued, enumerating, reconciling, completed, completedWithErrors, cancelled, failed
FileAvailability: available, missing, inaccessible, unstable
ProbeState: notRequested, queued, running, succeeded, unsupported, failed
ParseState: notRequested, queued, running, succeeded, ambiguous, failed
MatchState: unmatched, candidatesReady, verifying, proposed, confirmed, needsReview, rejected, failed
MatchSource: deterministic, metadataCandidate, llmVerified, manual, persistedRule, imported
WatchStatus: unwatched, inProgress, watched
JobState: pending, running, retryScheduled, completed, cancelled, deadLetter
```

Do not persist enum ordinal values. Persist stable text codes.

---

<a id="section-6"></a>
## 6. Database design

Use SQLite through Drift. Open the database on a Drift-managed background isolate or equivalent current recommended setup. Enable foreign keys. Use WAL mode where supported and appropriate. Use transactions for reconciliation and multi-table match commits.

### 6.1 General database rules

- All tables have explicit primary keys.
- All foreign keys declare deletion behavior intentionally.
- User history and audit records should usually use `RESTRICT` or soft-deletion semantics rather than cascade loss.
- Provider cache tables may cascade from their canonical parent.
- Add indexes based on actual query paths below.
- Store raw provider JSON only when useful for debugging/reprocessing; compress or omit it if size becomes material.
- Store normalized searchable fields separately from display strings.
- Use `createdAtUtc` and `updatedAtUtc` consistently.
- Keep schema snapshots and generated migration tests in source control.

### 6.2 `profiles`

Even though MVP exposes one profile, all watch state must be profile-scoped.

Columns:

```text
id                    INTEGER PRIMARY KEY AUTOINCREMENT
stableKey             TEXT NOT NULL UNIQUE
name                  TEXT NOT NULL
isDefault             INTEGER NOT NULL DEFAULT 0
createdAtUtc          INTEGER NOT NULL
updatedAtUtc          INTEGER NOT NULL
```

Create exactly one default profile during initial database creation.

### 6.3 `library_roots`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
stableKey                  TEXT NOT NULL UNIQUE
storageKind                TEXT NOT NULL
locator                     TEXT NOT NULL
locatorHash                 TEXT NOT NULL UNIQUE
displayName                 TEXT NOT NULL
isEnabled                   INTEGER NOT NULL DEFAULT 1
availability                TEXT NOT NULL
permissionFlags             INTEGER NULL
lastScanStartedAtUtc        INTEGER NULL
lastSuccessfulScanAtUtc     INTEGER NULL
lastCompletedScanId         TEXT NULL
lastKnownFileCount          INTEGER NOT NULL DEFAULT 0
lastErrorCode               TEXT NULL
lastErrorSafeDetail         TEXT NULL
createdAtUtc                INTEGER NOT NULL
updatedAtUtc                INTEGER NOT NULL
```

`locator` is a SAF tree URI on Android or normalized absolute path on native desktop. Never display it by default; use `displayName`.

### 6.4 `scan_runs`

Columns:

```text
id                         TEXT PRIMARY KEY              # UUID
rootId                     INTEGER NOT NULL REFERENCES library_roots(id)
mode                       TEXT NOT NULL
state                      TEXT NOT NULL
startedAtUtc               INTEGER NOT NULL
finishedAtUtc              INTEGER NULL
enumeratedFileCount        INTEGER NOT NULL DEFAULT 0
classifiedVideoCount       INTEGER NOT NULL DEFAULT 0
classifiedSubtitleCount    INTEGER NOT NULL DEFAULT 0
ignoredCount               INTEGER NOT NULL DEFAULT 0
newCount                   INTEGER NOT NULL DEFAULT 0
changedCount               INTEGER NOT NULL DEFAULT 0
movedCount                 INTEGER NOT NULL DEFAULT 0
missingCount               INTEGER NOT NULL DEFAULT 0
errorCount                 INTEGER NOT NULL DEFAULT 0
scannerVersion             INTEGER NOT NULL
appVersion                 TEXT NOT NULL
failureCode                TEXT NULL
failureSafeDetail          TEXT NULL
```

Indexes:

```text
(rootId, startedAtUtc DESC)
(state, startedAtUtc)
```

### 6.5 `library_files`

This table stores every discovered physical file, including ignored items, because reconciliation and diagnostics require a physical inventory.

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
rootId                     INTEGER NOT NULL REFERENCES library_roots(id)
storageKey                 TEXT NOT NULL
parentStorageKey           TEXT NULL
relativePath               TEXT NOT NULL
displayName                TEXT NOT NULL
normalizedName             TEXT NOT NULL
extensionLower             TEXT NOT NULL
mimeType                   TEXT NULL
fileKind                   TEXT NOT NULL
sizeBytes                  INTEGER NULL
modifiedAtUtc              INTEGER NULL
firstSeenAtUtc             INTEGER NOT NULL
lastSeenAtUtc              INTEGER NOT NULL
lastSeenScanId             TEXT NOT NULL REFERENCES scan_runs(id)
availability               TEXT NOT NULL
stabilityState             TEXT NOT NULL
quickFingerprint           TEXT NULL
fingerprintVersion         INTEGER NULL
ignoreReasonCode           TEXT NULL
isHidden                   INTEGER NOT NULL DEFAULT 0
isSystemArtifact           INTEGER NOT NULL DEFAULT 0
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
```

Constraints and indexes:

```text
UNIQUE(rootId, storageKey)
INDEX(rootId, relativePath)
INDEX(rootId, lastSeenScanId)
INDEX(fileKind, availability)
INDEX(quickFingerprint)
INDEX(normalizedName)
```

On SAF, `storageKey` must be derived from provider authority plus opaque document ID, not from parsing the URI or assuming a real filesystem path.

### 6.6 `sidecar_links`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
videoFileId                INTEGER NOT NULL REFERENCES library_files(id)
sidecarFileId              INTEGER NOT NULL REFERENCES library_files(id)
relationshipKind           TEXT NOT NULL              # subtitle, artwork, metadata
languageTag                TEXT NULL
isForced                   INTEGER NOT NULL DEFAULT 0
isDefault                  INTEGER NOT NULL DEFAULT 0
confidence                 INTEGER NOT NULL            # deterministic 0..100 score
source                     TEXT NOT NULL
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
UNIQUE(videoFileId, sidecarFileId)
```

### 6.7 `media_probes`

One-to-one with a video library file.

Columns:

```text
fileId                     INTEGER PRIMARY KEY REFERENCES library_files(id)
state                      TEXT NOT NULL
durationMs                 INTEGER NULL
containerFormat            TEXT NULL
width                      INTEGER NULL
height                     INTEGER NULL
rotationDegrees            INTEGER NULL
frameRate                  REAL NULL
videoCodec                 TEXT NULL
videoBitDepth              INTEGER NULL
audioCodecSummary          TEXT NULL
hdrFormat                  TEXT NULL
chapterCount               INTEGER NULL
probeVersion               INTEGER NOT NULL
probedAtUtc                INTEGER NULL
sourceFingerprint          TEXT NULL
failureCode                TEXT NULL
failureSafeDetail          TEXT NULL
rawSummaryJson             TEXT NULL
```

A probe is stale when `sourceFingerprint` no longer equals the current file fingerprint or when `probeVersion` changes.

### 6.8 `media_streams`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
fileId                     INTEGER NOT NULL REFERENCES library_files(id)
streamIndex                INTEGER NOT NULL
streamType                 TEXT NOT NULL              # video, audio, subtitle
codec                      TEXT NULL
languageTag                TEXT NULL
title                      TEXT NULL
isDefault                  INTEGER NOT NULL DEFAULT 0
isForced                   INTEGER NOT NULL DEFAULT 0
channels                   INTEGER NULL
sampleRate                 INTEGER NULL
width                      INTEGER NULL
height                     INTEGER NULL
bitRate                    INTEGER NULL
extraJson                  TEXT NULL
UNIQUE(fileId, streamIndex, streamType)
```

### 6.9 `parsed_media_hints`

Columns:

```text
fileId                     INTEGER PRIMARY KEY REFERENCES library_files(id)
parserVersion              INTEGER NOT NULL
parseState                 TEXT NOT NULL
mediaKindGuess             TEXT NOT NULL
titleCandidatePrimary      TEXT NULL
titleCandidatesJson        TEXT NOT NULL
year                       INTEGER NULL
seasonNumber               INTEGER NULL
episodeNumbersJson         TEXT NOT NULL
episodeSuffix              TEXT NULL
episodeTitleCandidate      TEXT NULL
specialHint                TEXT NULL
languageHintsJson          TEXT NOT NULL
releaseTagsJson            TEXT NOT NULL
qualityHintsJson           TEXT NOT NULL
confidenceScore            INTEGER NOT NULL
reasonCodesJson            TEXT NOT NULL
parsedAtUtc                INTEGER NOT NULL
rawParseJson               TEXT NOT NULL
```

The raw parse result is versioned and must preserve evidence from both folder and filename.

### 6.10 `canonical_titles`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
provider                   TEXT NOT NULL
providerId                 TEXT NOT NULL
mediaKind                  TEXT NOT NULL
name                       TEXT NOT NULL
normalizedName             TEXT NOT NULL
originalName               TEXT NULL
originalLanguage           TEXT NULL
releaseYear                INTEGER NULL
firstAirDate               TEXT NULL
releaseDate                TEXT NULL
overview                   TEXT NULL
status                     TEXT NULL
runtimeMinutes             INTEGER NULL
canonicalSeasonCount       INTEGER NULL
canonicalEpisodeCount      INTEGER NULL
posterPath                 TEXT NULL
backdropPath               TEXT NULL
metadataLanguage           TEXT NOT NULL
providerUpdatedAtUtc       INTEGER NULL
fetchedAtUtc               INTEGER NOT NULL
rawJson                    TEXT NULL
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
UNIQUE(provider, providerId, mediaKind)
```

### 6.11 `title_aliases`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
titleId                    INTEGER NOT NULL REFERENCES canonical_titles(id)
alias                      TEXT NOT NULL
normalizedAlias            TEXT NOT NULL
languageTag                TEXT NULL
countryCode                TEXT NULL
source                     TEXT NOT NULL
UNIQUE(titleId, normalizedAlias, languageTag, countryCode)
INDEX(normalizedAlias)
```

Manual aliases and provider aliases coexist. Manual aliases must not be overwritten by refresh.

### 6.12 `canonical_seasons`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
titleId                    INTEGER NOT NULL REFERENCES canonical_titles(id)
providerSeasonId           TEXT NULL
seasonNumber               INTEGER NOT NULL
name                       TEXT NULL
overview                   TEXT NULL
airDate                    TEXT NULL
posterPath                 TEXT NULL
episodeCount               INTEGER NULL
orderingKey                TEXT NOT NULL DEFAULT 'default'
fetchedAtUtc               INTEGER NOT NULL
rawJson                    TEXT NULL
UNIQUE(titleId, seasonNumber, orderingKey)
```

Season zero/specials are valid and must not be discarded.

### 6.13 `canonical_episodes`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
seasonId                   INTEGER NOT NULL REFERENCES canonical_seasons(id)
titleId                    INTEGER NOT NULL REFERENCES canonical_titles(id)
providerEpisodeId          TEXT NULL
seasonNumber               INTEGER NOT NULL
episodeNumber              INTEGER NOT NULL
absoluteNumber             INTEGER NULL
segmentCode                TEXT NULL
name                       TEXT NOT NULL
normalizedName             TEXT NOT NULL
overview                   TEXT NULL
airDate                    TEXT NULL
runtimeMinutes             INTEGER NULL
stillPath                  TEXT NULL
orderingKey                TEXT NOT NULL DEFAULT 'default'
fetchedAtUtc               INTEGER NOT NULL
rawJson                    TEXT NULL
UNIQUE(titleId, seasonNumber, episodeNumber, orderingKey, segmentCode)
INDEX(titleId, seasonNumber, episodeNumber)
INDEX(normalizedName)
```

`segmentCode` and `orderingKey` exist because some animated shows and release packs use segment-level numbering while broadcast platforms combine segments differently. Never assume one ordering is universally correct.

### 6.14 `external_ids`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
entityType                 TEXT NOT NULL              # title, season, episode
localEntityId              INTEGER NOT NULL
source                     TEXT NOT NULL              # imdb, tvdb, wikidata, etc.
externalId                 TEXT NOT NULL
UNIQUE(entityType, localEntityId, source)
INDEX(source, externalId)
```

### 6.15 `file_title_links`

Columns:

```text
fileId                     INTEGER PRIMARY KEY REFERENCES library_files(id)
titleId                    INTEGER NOT NULL REFERENCES canonical_titles(id)
state                      TEXT NOT NULL
source                     TEXT NOT NULL
deterministicScore         INTEGER NULL
llmDecisionLabel           TEXT NULL
reasonCodesJson            TEXT NOT NULL
warningsJson               TEXT NOT NULL
matchAttemptId             TEXT NULL
matchingRuleId             INTEGER NULL
isManuallyConfirmed        INTEGER NOT NULL DEFAULT 0
confirmedAtUtc             INTEGER NULL
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
```

A physical file can have only one active canonical title link. Candidate history belongs in match-attempt tables, not multiple active rows here.

### 6.16 `file_episode_links`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
fileId                     INTEGER NOT NULL REFERENCES library_files(id)
episodeId                  INTEGER NOT NULL REFERENCES canonical_episodes(id)
linkOrder                  INTEGER NOT NULL
segmentStartMs             INTEGER NULL
segmentEndMs               INTEGER NULL
source                     TEXT NOT NULL
confidenceScore            INTEGER NULL
reasonCodesJson            TEXT NOT NULL
isManuallyConfirmed        INTEGER NOT NULL DEFAULT 0
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
UNIQUE(fileId, episodeId)
INDEX(episodeId, fileId)
```

For multi-episode files without chapters or known boundaries, `segmentStartMs` and `segmentEndMs` remain null. In that case the UI presents file-level progress such as `S01E01–E03` and does not pretend to know which segment is currently playing.

### 6.17 `match_attempts`

Columns:

```text
id                         TEXT PRIMARY KEY             # UUID
scopeKind                  TEXT NOT NULL               # file, group, title, episodeBatch
scopeKey                   TEXT NOT NULL
inputHash                  TEXT NOT NULL
promptVersion              INTEGER NULL
provider                   TEXT NULL
llmProvider                TEXT NULL
llmModel                   TEXT NULL
state                      TEXT NOT NULL
selectedCandidateKey       TEXT NULL
resultLabel                TEXT NULL
reasonCodesJson            TEXT NOT NULL
warningsJson               TEXT NOT NULL
sanitizedRequestJson       TEXT NULL
sanitizedResponseJson      TEXT NULL
inputTokenCount            INTEGER NULL
outputTokenCount           INTEGER NULL
estimatedCostMicros        INTEGER NULL
startedAtUtc               INTEGER NOT NULL
finishedAtUtc              INTEGER NULL
failureCode                TEXT NULL
failureSafeDetail          TEXT NULL
UNIQUE(scopeKind, scopeKey, inputHash, promptVersion)
```

### 6.18 `match_candidates`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
matchAttemptId             TEXT NOT NULL REFERENCES match_attempts(id)
candidateKey               TEXT NOT NULL
canonicalTitleId           INTEGER NOT NULL REFERENCES canonical_titles(id)
rank                       INTEGER NOT NULL
deterministicScore         INTEGER NOT NULL
scoreBreakdownJson         TEXT NOT NULL
contradictionCodesJson     TEXT NOT NULL
UNIQUE(matchAttemptId, candidateKey)
```

The LLM returns `candidateKey`, not a free-form provider ID.

### 6.19 `matching_rules`

Columns:

```text
id                         INTEGER PRIMARY KEY AUTOINCREMENT
rootId                     INTEGER NULL REFERENCES library_roots(id)
ruleKind                   TEXT NOT NULL              # folderPrefix, normalizedTitleAlias, filenameRegex, exactStorageKey
pattern                    TEXT NOT NULL
normalizedPattern          TEXT NULL
titleId                    INTEGER NOT NULL REFERENCES canonical_titles(id)
seasonNumber               INTEGER NULL
priority                   INTEGER NOT NULL DEFAULT 100
isEnabled                  INTEGER NOT NULL DEFAULT 1
isUserApproved             INTEGER NOT NULL DEFAULT 1
createdBy                  TEXT NOT NULL
description                TEXT NULL
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
```

Do not execute an LLM-generated regex automatically. Regex rules require deterministic escaping/validation and explicit user approval.

### 6.20 `file_playback_states`

Columns:

```text
profileId                  INTEGER NOT NULL REFERENCES profiles(id)
fileId                     INTEGER NOT NULL REFERENCES library_files(id)
sourceFingerprint          TEXT NULL
positionMs                 INTEGER NOT NULL DEFAULT 0
durationMs                 INTEGER NULL
status                     TEXT NOT NULL
playCount                  INTEGER NOT NULL DEFAULT 0
firstPlayedAtUtc           INTEGER NULL
lastPlayedAtUtc            INTEGER NULL
completedAtUtc             INTEGER NULL
lastAudioLanguage          TEXT NULL
lastSubtitleLanguage       TEXT NULL
lastSubtitleEnabled        INTEGER NULL
updatedAtUtc               INTEGER NOT NULL
PRIMARY KEY(profileId, fileId)
INDEX(profileId, lastPlayedAtUtc DESC)
```

If the file fingerprint changes, preserve the old record for diagnostics or explicitly reset position according to a documented migration policy; do not blindly seek into a replaced file.

### 6.21 `episode_watch_states`

Columns:

```text
profileId                  INTEGER NOT NULL REFERENCES profiles(id)
episodeId                  INTEGER NOT NULL REFERENCES canonical_episodes(id)
status                     TEXT NOT NULL
lastFileId                 INTEGER NULL REFERENCES library_files(id)
positionMs                 INTEGER NULL
durationMs                 INTEGER NULL
completedAtUtc             INTEGER NULL
updatedAtUtc               INTEGER NOT NULL
PRIMARY KEY(profileId, episodeId)
INDEX(profileId, status)
```

This table supports canonical watched state even when an episode later receives a different physical release.

### 6.22 `episode_file_preferences`

Columns:

```text
profileId                  INTEGER NOT NULL REFERENCES profiles(id)
episodeId                  INTEGER NOT NULL REFERENCES canonical_episodes(id)
preferredFileId            INTEGER NOT NULL REFERENCES library_files(id)
source                     TEXT NOT NULL              # automatic or manual
updatedAtUtc               INTEGER NOT NULL
PRIMARY KEY(profileId, episodeId)
```

### 6.23 `jobs`

Columns:

```text
id                         TEXT PRIMARY KEY
type                       TEXT NOT NULL
dedupeKey                  TEXT NOT NULL
payloadJson                TEXT NOT NULL
state                      TEXT NOT NULL
priority                   INTEGER NOT NULL
attemptCount               INTEGER NOT NULL DEFAULT 0
maxAttempts                INTEGER NOT NULL
nextAttemptAtUtc           INTEGER NULL
lockedAtUtc                INTEGER NULL
lastHeartbeatAtUtc         INTEGER NULL
createdAtUtc               INTEGER NOT NULL
updatedAtUtc               INTEGER NOT NULL
completedAtUtc             INTEGER NULL
failureCode                TEXT NULL
failureSafeDetail          TEXT NULL
UNIQUE(type, dedupeKey)
INDEX(state, priority DESC, nextAttemptAtUtc)
```

Initial job types:

```text
probeFile
parseFile
associateSidecars
buildLocalGroup
searchMetadataCandidates
fetchTitleMetadata
fetchSeasonMetadata
verifyTitleWithLlm
mapEpisodes
verifyEpisodesWithLlm
generateThumbnail
recomputeWatchState
```

### 6.24 `app_settings`

Store non-secret settings here. Secrets belong in secure storage.

Columns:

```text
key                        TEXT PRIMARY KEY
valueJson                  TEXT NOT NULL
updatedAtUtc               INTEGER NOT NULL
```

Required settings include:

- preferred metadata language;
- fallback metadata language;
- preferred audio languages;
- preferred subtitle languages;
- subtitle default behavior;
- LLM verification mode;
- auto-match policy;
- watched threshold percentage;
- watched maximum remaining duration;
- auto-play-next setting;
- scan-on-start setting;
- include specials in progress;
- diagnostic logging level.

### 6.25 Required database views/queries

Implement tested DAO queries for:

- home Continue Watching items;
- next episode per title;
- title cards with availability and watch progress;
- movie details with physical versions;
- show details with season summaries;
- episode rows with availability, selected version, and watch status;
- unresolved/needs-review queue;
- root health and last scan;
- scan progress counters;
- duplicate physical versions per canonical episode/movie;
- orphaned sidecars;
- stale probes;
- dead-letter jobs;
- local files not seen by the latest successful scan;
- recently added titles based on physical file first-seen time.

### 6.26 Migration policy

After schema version 1 is committed:

1. Bump the Drift schema version for every schema change.
2. Generate schema snapshots and step-by-step migration helpers using current Drift tooling.
3. Write or update migration tests.
4. Run foreign-key integrity checks.
5. Preserve user mappings, aliases, playback state, and rules unless a documented migration explicitly transforms them.
6. Never solve development migration failures by deleting production user data.

---

<a id="section-7"></a>
## 7. Storage abstraction and Android filesystem access

### 7.1 Storage boundary

The rest of the application must not know whether a file came from a native path, Android SAF URI, removable storage, or a future network adapter.

Define domain-facing value objects similar to:

```dart
final class LibraryRootLocator {
  const LibraryRootLocator({
    required this.storageKind,
    required this.opaqueValue,
  });

  final StorageKind storageKind;
  final String opaqueValue;
}

final class StorageEntrySnapshot {
  const StorageEntrySnapshot({
    required this.storageKey,
    required this.parentStorageKey,
    required this.relativePath,
    required this.displayName,
    required this.isDirectory,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAtUtc,
    required this.flags,
  });

  final String storageKey;
  final String? parentStorageKey;
  final String relativePath;
  final String displayName;
  final bool isDirectory;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modifiedAtUtc;
  final Set<StorageEntryFlag> flags;
}
```

Expected gateway behavior:

```dart
abstract interface class LibraryStorageGateway {
  Future<AppResult<AuthorizedLibraryRoot>> chooseRoot();

  Future<AppResult<List<AuthorizedLibraryRoot>>> listPersistedRoots();

  Future<AppResult<RootAccessStatus>> checkAccess(LibraryRootLocator root);

  Stream<StorageScanEvent> enumerateRecursively({
    required LibraryRootLocator root,
    required String scanId,
    required CancellationToken cancellationToken,
  });

  Future<AppResult<StorageEntrySnapshot>> stat({
    required LibraryRootLocator root,
    required String storageKey,
  });

  Future<AppResult<SmallFileContent>> readSmallFile({
    required LibraryRootLocator root,
    required String storageKey,
    required int maximumBytes,
  });

  Future<AppResult<PlaybackSourceLease>> openForPlayback({
    required LibraryRootLocator root,
    required String storageKey,
  });

  Future<void> releasePlaybackLease(PlaybackSourceLease lease);

  Future<AppResult<void>> releaseRootPermission(LibraryRootLocator root);
}
```

`PlaybackSourceLease` must own the lifecycle of any content URI permission reference, native file descriptor, loopback proxy token, or other resource required by the player.

### 7.2 Android Storage Access Framework requirements

Use `ACTION_OPEN_DOCUMENT_TREE` to let the user authorize a media directory. Persist the granted read permission using the flags returned by the picker. Request write permission only if a future feature actually requires modifying files; MVP is read-only.

The Android adapter must:

- persist the tree URI;
- persist read access across reboots;
- detect revoked or invalid permission;
- enumerate all descendants without assuming native paths;
- treat document IDs as opaque;
- expose display names and a synthesized root-relative path for diagnostics and matching;
- tolerate providers that omit size or modification time;
- cancel enumeration;
- return batched results to avoid thousands of platform-channel round trips;
- avoid loading the entire directory tree into memory at once;
- close every cursor, descriptor, and stream deterministically;
- perform expensive enumeration off the main Android UI thread;
- handle removable storage disappearance without deleting catalog history.

### 7.3 Typed platform contract

Prefer Pigeon for request/response objects. If current Pigeon streaming support is insufficient, use Pigeon for commands and one EventChannel for scan batches.

Suggested host API contract:

```text
StorageHostApi.chooseDirectory(initialUri?) -> AuthorizedRootMessage
StorageHostApi.listPersistedPermissions() -> List<AuthorizedRootMessage>
StorageHostApi.checkRoot(treeUri) -> RootAccessMessage
StorageHostApi.startScan(treeUri, scanId, options) -> void
StorageHostApi.cancelScan(scanId) -> void
StorageHostApi.stat(treeUri, storageKey) -> StorageEntryMessage
StorageHostApi.readSmallFile(treeUri, storageKey, maxBytes) -> ByteData
StorageHostApi.openPlaybackSource(treeUri, storageKey) -> PlaybackLeaseMessage
StorageHostApi.closePlaybackSource(leaseId) -> void
StorageHostApi.releasePermission(treeUri) -> void
```

Event channel messages:

```json
{
  "scanId": "uuid",
  "eventType": "batch",
  "entries": [
    {
      "storageKey": "authority|opaque-document-id",
      "parentStorageKey": "...",
      "relativePath": "TV Shows/Bluey/...mp4",
      "displayName": "...mp4",
      "isDirectory": false,
      "mimeType": "video/mp4",
      "sizeBytes": 123456789,
      "modifiedAtEpochMs": 1700000000000,
      "flags": 0
    }
  ]
}
```

Other event types:

```text
started
batch
progress
warning
completed
cancelled
failed
```

Every event carries `scanId`. Ignore events for unknown or completed scan IDs.

### 7.4 Android enumeration implementation

For large trees, prefer direct `DocumentsContract` cursor queries over recursively constructing large `DocumentFile` object graphs. The implementation may use `DocumentFile` for initial correctness, but benchmark it with the real fixture and replace it if traversal is unacceptably slow.

Enumeration algorithm:

1. Validate persisted permission.
2. Resolve the root document ID.
3. Initialize a queue containing the root directory descriptor.
4. While the queue is not empty and cancellation is not requested:
   - query children with the minimal required projection;
   - synthesize child relative paths from parent path plus display name;
   - create a stable storage key from authority and document ID;
   - enqueue directories;
   - accumulate files into a batch;
   - emit a batch when count or serialized size reaches a configured threshold;
   - periodically emit progress and heartbeat events.
5. Emit the final partial batch.
6. Emit completed only after all cursors close successfully.
7. On provider error, emit failed with a safe code and do not claim a complete snapshot.

Recommended cursor projection:

```text
COLUMN_DOCUMENT_ID
COLUMN_DISPLAY_NAME
COLUMN_MIME_TYPE
COLUMN_SIZE
COLUMN_LAST_MODIFIED
COLUMN_FLAGS
```

Never parse `COLUMN_DOCUMENT_ID` for path semantics.

### 7.5 Playback-source risk spike

Before implementing the full application, prove that a selected SAF video can be played and seeked without copying the complete file. This is Milestone 0 and blocks later work.

Implement `PlaybackSourceResolver` with strategies in this order:

1. **Direct content URI** if the selected media backend supports it reliably on target tablets.
2. **Native file-descriptor bridge** if the backend supports an `fd://`-style source or equivalent.
3. **Loopback range proxy** bound only to `127.0.0.1`, serving bytes from a `ParcelFileDescriptor` with HTTP Range support.

The final solution must support:

- opening a large MKV and MP4;
- seeking forward and backward;
- pause/resume;
- app lifecycle interruption;
- accurate duration where available;
- closing resources when player exits;
- multiple sequential playback sessions without descriptor leaks;
- external SRT attachment;
- no full-file copy to temporary storage.

If a loopback proxy is required, it must:

- bind only to loopback;
- use a random unguessable per-lease token;
- reject unknown or expired tokens;
- support `HEAD` and `GET`;
- support single-range requests and return `206 Partial Content`;
- return correct `Content-Length`, `Content-Range`, `Accept-Ranges`, and MIME type;
- prevent directory traversal;
- close the descriptor on lease release;
- terminate when no leases remain or on app shutdown;
- never expose a root or arbitrary file-browsing endpoint.

### 7.6 Native desktop adapter

The desktop implementation uses normalized absolute paths internally but still exposes opaque storage keys to the domain.

Native adapter requirements:

- choose a directory with a maintained platform picker;
- recursively enumerate asynchronously;
- avoid following symbolic-link loops;
- define whether symlinks are ignored or followed and persist the decision;
- normalize path separators for matching while preserving native path for access;
- use case-sensitive or case-insensitive comparisons appropriate to the volume, but maintain a stable normalized comparison form;
- handle removable drives and network mount disappearance;
- support cancellation;
- optionally use filesystem watcher events as hints, never as the sole source of truth.

### 7.7 Storage identity

Identity and location are separate.

On Android SAF:

```text
storageKey = providerAuthority + "|" + opaqueDocumentId
```

On native filesystems, prefer a stable file identity if exposed by the platform. Otherwise use a versioned composite of:

```text
normalized absolute path
size
modified time
optional quick fingerprint
```

A rename or move should be detected by stable storage identity where possible. Where it is not, a quick fingerprint can reconcile a missing old path and new path into a probable move.

### 7.8 Quick fingerprint

Do not hash complete videos during normal scans.

Define version 1 as a cryptographic hash over:

```text
file size encoded canonically
first N bytes
last N bytes when random access is available and file is large enough
```

Recommended `N`: configurable, initially 1 MiB or 4 MiB after benchmark.

Rules:

- Compute only for new files, changed files, possible moves, duplicates, or explicit diagnostics.
- Record the fingerprint version.
- Treat a matching quick fingerprint as strong evidence, not mathematical proof of identical full content.
- Never fingerprint unstable files that are still being copied.
- Rate-limit hashing to avoid battery and storage contention.

### 7.9 File stability

A newly discovered or changed file may still be synchronizing. Mark it `unstable` when:

- modified time is very recent;
- size changes between observations;
- provider reports incomplete metadata;
- opening returns transient errors;
- configured synchronization marker files indicate active transfer.

A file becomes stable when size and modified time remain unchanged across two observations separated by a configurable interval, or when it is older than a conservative stability window and opens successfully.

Do not probe, match, thumbnail, or autoplay an unstable file.

---

<a id="section-8"></a>
## 8. Scanning and reconciliation

### 8.1 Scan state machine

Use an explicit state machine:

```text
Queued
  → AccessValidation
  → Enumerating
  → Reconciling
  → SchedulingDerivedWork
  → Completed

Any active state may transition to:
  → Cancelled
  → Failed
  → CompletedWithErrors
```

Derived work such as probing and metadata lookup may continue after the physical enumeration is committed, but the scan UI must distinguish:

- filesystem scan complete;
- enrichment still running;
- metadata unavailable;
- review required.

### 8.2 Full reconciliation algorithm

A scan is a snapshot reconciliation, not merely “find files newer than last scan.”

For each root:

1. Create a `scan_runs` row in `queued` state.
2. Validate access and root availability.
3. Set root availability to `scanning` without erasing the previous available state needed for rollback.
4. Enumerate all physical entries into bounded in-memory batches.
5. For each batch, in a database transaction:
   - classify entries;
   - upsert by `(rootId, storageKey)`;
   - update path/name/metadata and `lastSeenScanId`;
   - identify new, changed, moved, and unchanged entries;
   - enqueue only required downstream work using dedupe keys.
6. After enumeration succeeds completely, run final reconciliation in a transaction:
   - mark previously available entries not seen in this scan as `missing`;
   - do not delete them;
   - update root scan timestamps and counts;
   - mark scan completed or completed-with-errors.
7. If enumeration fails or is cancelled:
   - retain entries already upserted as seen;
   - do not mark unseen entries missing;
   - retain the previous successful-scan timestamp;
   - mark scan failed/cancelled;
   - restore an appropriate root availability state.

### 8.3 Change classification

For an existing entry:

- **unchanged:** storage key, size, modified time, and relevant flags unchanged;
- **metadata changed:** same identity, changed path/name or provider metadata;
- **content probably changed:** size or modified time changed;
- **moved/renamed:** same stable identity with changed relative path;
- **probable move:** old missing item and new item share quick fingerprint;
- **reappeared:** previously missing item is seen again;
- **inaccessible:** entry exists but cannot be read;
- **unstable:** currently changing.

Invalidate downstream states selectively:

```text
path/name only changed:
  reparse and regroup; retain probe if fingerprint unchanged

size/content changed:
  invalidate probe, parse if filename changed, title/episode links only if evidence changed,
  and validate playback state fingerprint

sidecar changed:
  reassociate sidecars; do not re-fetch title metadata

root renamed:
  update display locator only; do not rematch all files
```

### 8.4 Startup scan policy

At startup:

1. Render the cached catalog immediately.
2. Validate roots asynchronously.
3. If scan-on-start is enabled and no scan is already running, queue reconciliation.
4. Show non-blocking scan status.
5. Never hold the splash screen until the full library is scanned.

### 8.5 Incremental hints

Filesystem watcher events, MediaStore changes, or Syncthing marker updates may schedule targeted scans. They are hints only. Run periodic/full reconciliation according to settings.

Deduplicate noisy events by root and debounce them. A targeted scan must never mark files outside its proven scope as missing.

### 8.6 Classification

Classify by filename, extension, MIME type, and artifact rules.

Initial video extensions:

```text
.mkv .mp4 .m4v .avi .mov .webm .mpg .mpeg .ts .m2ts .mts
.vob .ogv .flv .wmv .asf .3gp .3g2 .divx .rm .rmvb
```

Initial subtitle extensions:

```text
.srt .ass .ssa .vtt .sub .idx .sup
```

Initial artwork extensions:

```text
.jpg .jpeg .png .webp .avif
```

Initial metadata/checksum/noise:

```text
.nfo .xml .json .sfv .md5 .sha1 .sha256 .txt .url .gitkeep
```

Rules:

- Ignore any basename beginning `._` before extension classification.
- Ignore `.DS_Store`, `Thumbs.db`, Syncthing marker directories, and known hidden filesystem artifacts.
- Do not assume every `.txt` is irrelevant forever; classify it as ignored text with reason code.
- Do not trust extension alone for playback capability. Probe or attempt playback.
- Do not reject uppercase extensions.
- Preserve original extension and MIME evidence.

### 8.7 Ignore reason codes

Use stable reason codes such as:

```text
APPLEDOUBLE_RESOURCE_FORK
OS_METADATA_FILE
SYNCTHING_MARKER
CHECKSUM_FILE
RELEASE_INFO_TEXT
LOCAL_ARTWORK_CANDIDATE
SUBTITLE_SIDECAR
UNSUPPORTED_EXTENSION
DIRECTORY_ENTRY
HIDDEN_FILE
ZERO_LENGTH_FILE
```

Ignored entries remain visible in diagnostics, not normal catalog UI.

### 8.8 Sidecar association

For each video, look for sibling sidecars with a normalized stem.

Examples:

```text
Bluey S01E01 - The Magic Xylophone.mp4
Bluey S01E01 - The Magic Xylophone.en.srt
```

Language parsing should recognize BCP-47-like and common legacy forms:

```text
.en.srt
.en-US.srt
.cs.srt
.cz.srt       # normalize to cs with original retained
.sk.srt
.forced.en.srt
.en.forced.srt
.default.srt
```

Association score inputs:

- exact normalized stem;
- stem after stripping language/forced/default suffixes;
- same directory;
- unique candidate;
- episode tokens agree;
- title tokens agree.

Never attach one subtitle to multiple unrelated videos solely because it is named `subtitle.srt`. Mark ambiguous orphan sidecars for diagnostics.

### 8.9 Local artwork priority

Recognize conventional folder artwork names:

```text
poster.*
folder.*
cover.*
fanart.*
backdrop.*
logo.*
season01-poster.*
```

Artwork selection priority:

1. user-selected local override;
2. exact conventional local artwork;
3. provider artwork in preferred language;
4. provider artwork without language;
5. generated frame thumbnail;
6. deterministic placeholder.

Do not treat release-site promotional JPG files as authoritative posters without matching evidence.

### 8.10 Scan performance requirements

On the target tablet and the supplied 1,168-entry fixture:

- enumeration must stream progress rather than freeze UI;
- database writes must be batched;
- peak Dart memory for listing import should remain bounded and measured;
- first visible cached home screen should render independently of scan;
- cancellation should take effect within a few seconds at worst;
- re-scan of unchanged fixture should schedule near-zero probe/metadata work;
- no more than a bounded number of concurrent file descriptors may be open;
- battery-intensive probing and hashing concurrency defaults to 1 on tablets, configurable after measurement.

Add benchmark output to `docs/performance.md` before release.

---

<a id="section-9"></a>
## 9. Filename and folder parser

The parser is a pure Dart package with no Flutter, database, provider, LLM, or filesystem dependencies.

### 9.1 Parser input

```dart
final class MediaParseInput {
  const MediaParseInput({
    required this.fileName,
    required this.relativePath,
    required this.parentFolderNames,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.durationHint,
  });
}
```

### 9.2 Parser output

```dart
final class MediaParseResult {
  const MediaParseResult({
    required this.mediaKindGuess,
    required this.titleCandidates,
    required this.year,
    required this.seasonNumber,
    required this.episodeReferences,
    required this.episodeTitleCandidate,
    required this.specialHint,
    required this.languageHints,
    required this.releaseTags,
    required this.qualityHints,
    required this.reasonCodes,
    required this.confidenceScore,
    required this.normalizationTrace,
  });
}
```

An episode reference contains:

```text
number
optional suffix
source span
reference kind: explicit, range-expanded, chained, naturalLanguage, folderInherited
```

### 9.3 Parsing pipeline

Implement stages, not one monolithic regex:

1. Preserve original filename and path.
2. Remove extension for analysis.
3. Unicode-normalize to NFKC for comparison while retaining original text.
4. Normalize typographic apostrophes, separators, repeated whitespace, and dot/underscore release separators in a comparison copy.
5. Parse structural TV markers before stripping release noise.
6. Parse year candidates.
7. Parse explicit quality, codec, source, audio, HDR, and release-group tags.
8. Infer title candidates from filename and parent folders.
9. Parse episode title candidate from text after structural markers and before quality tags.
10. Infer media type from evidence, not root folder alone.
11. Produce reason codes and confidence.
12. Never mutate the user file.

### 9.4 Supported TV grammars

Implement independent parser strategies with precedence and tests:

#### `SxxExx`

```regex
(?i)\bS(?<season>\d{1,3})[ ._-]*E(?<episode>\d{1,4})(?<suffix>[A-Za-z])?\b
```

The production regex may differ to correctly handle chained/range forms, but behavior must match.

#### Chained episodes

```text
S02E07E08
S01E01E02E03
```

All episode numbers inherit the parsed season.

#### Episode ranges

```text
S01E01-E03
S01E01-03
S01E01 to E03
```

Expand only reasonable ascending ranges with a configured maximum span. Mark huge or descending ranges ambiguous rather than allocating unbounded lists.

#### `NxNN`

```text
1x07
02x044
```

#### Natural language

```text
Season 1 Episode 10
Season 1 - Ep 10
Series 1 Episode 10
```

#### Folder inheritance

```text
parent: Peppa.Pig.S06.x265
file: S06e01 - Pandi dvojcata.mp4
```

#### Specials

```text
S00E01
Special 5-0
Special
Christmas Special
```

Special text without canonical numbering must remain a hint.

#### Absolute numbering

Support an explicit absolute-number parser only when evidence is clear, for example anime-style `[123]`, and keep it disabled by default until fixtures justify it. Never interpret any arbitrary number as an episode.

### 9.5 Movie parsing

Movie evidence includes:

- title followed by a four-digit plausible release year;
- folder and filename agreeing on title/year;
- no explicit TV marker;
- duration plausibly feature length, when available;
- provider candidate consistency.

Examples:

```text
Zootopia (2016) (...).mkv
Astro.Kid.2019.1080p.BluRay....mp4
Willy a kouzelná planeta - Astro.Kid.2019....mkv
```

For mixed localized/original text, output multiple ordered title candidates rather than choosing one prematurely.

### 9.6 Release-noise vocabulary

Maintain a versioned token dictionary and tests. Initial categories:

```text
Resolution: 480p, 576p, 720p, 1080p, 1080i, 2160p, 4K, UHD
Source: WEB, WEBRip, WEB-DL, BluRay, BDRip, BRRip, DVDRip, HDTV, DSNP, NF, AMZN
Video: x264, x265, h264, h265, HEVC, AVC, AV1, VP9, 8bit, 10bit
Audio: AAC, AC3, EAC3, DDP, DTS, TrueHD, Atmos, 2.0, 5.1, 7.1
Dynamic range: HDR, HDR10, HDR10+, DV, Dolby Vision
Release groups/sites: bracketed or terminal groups such as YTS, Tigole, RCVR, eztv
Other: Complete, Repack, Proper, Extended, Directors Cut, Remux
```

Do not remove a token if it is plausibly part of a title in context. Record every removed token in `normalizationTrace`.

### 9.7 Title normalization

Comparison normalization should:

- lowercase with locale-independent rules;
- normalize Unicode;
- convert punctuation/separators to spaces;
- collapse whitespace;
- optionally remove leading articles only in a secondary comparison form;
- preserve numerals;
- preserve meaningful words such as `US`, `UK`, `The`, or `Part` in the primary form;
- transliterate only as an additional comparison key, never as the displayed title;
- support diacritics-insensitive comparison as a secondary key.

### 9.8 Parent-folder evidence

Use up to a bounded number of parent folders. Weight nearer parents more strongly. Ignore known root labels and release-only folders.

Example evidence:

```text
TV Shows / Prasiatko Peppa / S01 DVDRIP / 1x07 Maminka pracuje.mkv
```

Likely title candidates:

```text
Prasiatko Peppa
Peppa Pig               # only after alias/provider evidence, not parser invention
```

The pure parser should output `Prasiatko Peppa`; provider aliases or LLM candidate comparison can connect it to `Peppa Pig`.

### 9.9 Parser reason codes

Examples:

```text
EXPLICIT_SXXEXX
EXPLICIT_CHAINED_EPISODES
EXPLICIT_EPISODE_RANGE
EXPLICIT_NXNN
EXPLICIT_NATURAL_LANGUAGE_EPISODE
SEASON_FROM_PARENT_FOLDER
TITLE_FROM_FILENAME
TITLE_FROM_PARENT_FOLDER
YEAR_FROM_FILENAME
YEAR_FROM_PARENT_FOLDER
MOVIE_PATTERN_WITH_YEAR
TV_MARKER_PRESENT
LOCALIZED_TITLE_CANDIDATE
RELEASE_TAGS_REMOVED
EPISODE_SUFFIX_PRESENT
SPECIAL_TEXT_PRESENT
AMBIGUOUS_NUMERIC_TOKEN
CONFLICTING_FOLDER_AND_FILENAME
```

### 9.10 Parser confidence

Parser confidence is a deterministic internal score, not a probability.

Suggested interpretation:

```text
90–100: explicit, internally consistent structural markers
70–89: strong title/folder evidence with minor ambiguity
40–69: useful partial parse requiring metadata evidence
1–39: weak parse
0: no useful parse
```

Do not auto-match canonical metadata solely from parser confidence.

### 9.11 Parser tests

Tests must cover:

- every mandatory fixture pattern;
- punctuation and Unicode variants;
- uppercase/lowercase markers;
- zero-padding;
- large episode numbers;
- invalid ranges;
- suffix letters;
- title numbers that are not episodes;
- years that are not resolutions;
- dotted release names;
- localized characters;
- sidecar filenames;
- resource forks;
- parent-folder inheritance;
- deterministic output serialization.

Generate a fixture report containing:

```text
input
classification
primary title candidate
media kind guess
season
episodes
year
confidence
reason codes
```

Commit a reviewed snapshot for regression detection.

---

<a id="section-10"></a>
## 10. Local grouping

### 10.1 Purpose

Metadata and LLM calls occur at logical-group level wherever possible. A folder is evidence but not automatically one group.

### 10.2 Grouping signals

Use:

- normalized title candidates;
- parent folder hierarchy;
- common season markers;
- neighboring filenames;
- year;
- media-kind guess;
- duration distribution;
- language/release hints;
- known persisted matching rules.

### 10.3 Grouping rules

Strong grouping examples:

```text
All files in "Bluey (2018) Season 2 ..." with title Bluey and S02 markers
All files in "Peppa.Pig.S06.x265" with S06 markers and no filename title
```

Do not group solely by top-level `TV Shows` or `Movies`.

Movies generally form one group per probable title/year, even when a release folder contains images and subtitles.

### 10.4 Cross-folder merge candidates

After provider resolution, folders can merge under one canonical title. Before provider resolution, create merge candidates when normalized titles or aliases strongly agree.

Examples:

```text
Bluey Season 1 - Complete S01
Bluey (2018) Season 2 ...
Bluey (2018) Season 3 ...
```

and:

```text
Peppa Pig ...
Peppa.Pig.S06.x265
Prasiatko Peppa
```

The second case should remain lower confidence until provider alternative-title or user confirmation exists.

### 10.5 Group summary DTO

```dart
final class LocalMediaGroupSummary {
  const LocalMediaGroupSummary({
    required this.groupKey,
    required this.probableMediaKind,
    required this.titleCandidates,
    required this.yearCandidates,
    required this.seasons,
    required this.episodeRanges,
    required this.languages,
    required this.sampleFiles,
    required this.anomalyFiles,
    required this.fileCount,
  });
}
```

Select representative files deterministically:

- first and last episode of each season;
- several evenly spaced files;
- every parse anomaly;
- every multi-episode form;
- title-only files;
- files with conflicting years/titles;
- cap ordinary samples to control request size.

---

<a id="section-11"></a>
## 11. Metadata-provider architecture

### 11.1 Provider-neutral domain contract

The domain must not depend on TMDB DTOs.

```dart
abstract interface class MetadataProvider {
  String get providerKey;

  Future<AppResult<List<TitleSearchCandidate>>> searchTitles(
    TitleSearchRequest request,
  );

  Future<AppResult<CanonicalTitleSnapshot>> fetchTitle(
    ProviderTitleRef title,
    MetadataLocale locale,
  );

  Future<AppResult<List<CanonicalSeasonSnapshot>>> fetchSeasons(
    ProviderTitleRef title,
    MetadataLocale locale,
  );

  Future<AppResult<CanonicalSeasonWithEpisodes>> fetchSeason(
    ProviderTitleRef title,
    int seasonNumber,
    MetadataLocale locale,
  );

  Future<AppResult<List<TitleAliasSnapshot>>> fetchAliases(
    ProviderTitleRef title,
  );

  Future<AppResult<Map<String, String>>> fetchExternalIds(
    ProviderEntityRef entity,
  );

  Future<AppResult<ArtworkConfiguration>> fetchArtworkConfiguration();
}
```

Provider DTO conversion occurs inside `media_metadata`.

### 11.2 TMDB MVP adapter

Use TMDB as the first provider for title discovery, canonical metadata, seasons, episodes, artwork, alternative titles, and external IDs.

Expected API usage includes current equivalents of:

```text
/search/movie
/search/tv
/movie/{id}
/tv/{id}
/tv/{id}/season/{season_number}
movie/tv alternative titles
movie/tv/episode external IDs
/configuration
```

Use separate movie and TV search calls when media type evidence is strong. Use both when uncertain. Avoid unrestricted `multi` results containing people unless filtering is explicit.

### 11.3 Search request generation

For a local group, generate a bounded ordered list of search queries:

1. primary normalized title candidate;
2. localized title candidate;
3. title with parsed year;
4. title without release noise;
5. parent-folder title candidate;
6. manually configured alias.

Deduplicate equivalent queries. Stop when enough strong candidates exist.

Do not send season/episode release tags as part of the provider title query.

### 11.4 Candidate normalization

Convert provider search results into:

```dart
final class TitleSearchCandidate {
  const TitleSearchCandidate({
    required this.candidateKey,
    required this.provider,
    required this.providerId,
    required this.mediaKind,
    required this.name,
    required this.originalName,
    required this.releaseYear,
    required this.originalLanguage,
    required this.popularityHint,
    required this.posterPath,
    required this.overview,
  });
}
```

`candidateKey` is generated locally and is opaque to the LLM. It is stable only for the match attempt.

### 11.5 Candidate expansion

For the top bounded candidates, fetch enough detail to validate:

- alternative/localized titles;
- exact year/date;
- season existence;
- episode counts;
- sample episode names for observed season/episode tokens;
- external IDs;
- status and title type.

Do not fetch every episode of every weak candidate. Use progressive expansion:

```text
search results
→ deterministic preliminary score
→ expand top candidates
→ re-score
→ LLM verification
```

### 11.6 Metadata localization

Settings:

```text
preferred metadata locale, e.g. cs-CZ or en-US
fallback locale, normally en-US
preferred artwork languages
```

Rules:

- canonical provider ID is language-independent;
- display strings may be refreshed in the preferred language;
- retain original name and language;
- aliases are additive;
- episode matching may compare both localized and fallback names;
- translated local episode titles should not be considered contradictions when season/episode identifiers agree;
- manual display-title overrides are never overwritten by provider refresh.

### 11.7 Episode orderings

Some shows use conflicting segment, broadcast, DVD, production, or streaming orders. The application must represent ordering explicitly.

MVP behavior:

- store the provider default ordering as `default`;
- retain `orderingKey` on seasons and episodes;
- allow a title-level ordering override in settings or user correction;
- compare episode titles when local numbering and provider numbering disagree;
- never renumber physical files;
- preserve unresolved segment suffixes;
- support a future alternate-order provider without schema replacement.

For a title where the local pack uses segment-level episodes but the provider groups segments, the match system may:

1. select an alternate provider ordering if available;
2. map multiple local segment files to one canonical combined episode with segment metadata;
3. map one combined local file to multiple canonical segments;
4. require user review if neither representation is sufficiently supported.

The UI must not lie about exact per-segment playback position when segment boundaries are unknown.

### 11.8 HTTP client

Use one configured Dio client per provider with:

- base URL;
- authorization interceptor;
- request ID/correlation metadata;
- timeout policy;
- retry policy for retryable network errors and selected 5xx responses;
- explicit 429 handling honoring `Retry-After` where supplied;
- sanitized logging;
- cancellation support;
- JSON decoding off the UI-critical path where payloads are large.

Do not retry:

- invalid credentials;
- schema/contract errors without code change;
- 404 for a known removed entity unless refresh policy says otherwise;
- user cancellation.

### 11.9 Provider cache

Cache provider responses in the relational model and optionally an HTTP cache table.

Suggested refresh intervals:

```text
configuration: long-lived, refresh weekly or on failure
completed movie: 30–90 days
ended show: 30 days
returning show: 7 days
future/unaired season: 1 day
artwork URL configuration: provider-recommended duration
```

These are defaults, not hard promises. Refresh on explicit user request.

A provider outage must not remove existing catalog metadata.

### 11.10 Artwork URL construction and storage

Obtain provider image base configuration rather than hardcoding assumptions. Store provider-relative artwork paths in canonical tables and build concrete URLs in infrastructure.

Cache artwork files in the application cache directory using:

```text
provider
provider entity ID
path
requested size
content revision/hash when available
```

Use bounded cache eviction. Do not store duplicate full-size images when smaller display sizes suffice.

### 11.11 Attribution and terms

Create an About/Attribution screen. Include required metadata-provider attribution and logo/text according to the provider's current terms. Review terms before release. Store the current compliance decision in `docs/metadata_provider_compliance.md`.

### 11.12 Future providers

Keep extension points for:

- TVmaze;
- TheTVDB where licensing permits;
- OMDb for supplemental IMDb-centric movie data;
- local NFO metadata;
- manual-only titles;
- another provider selected by the user.

Do not merge provider-specific IDs into one unqualified `externalId` field.

---

<a id="section-12"></a>
## 12. Deterministic matching engine

### 12.1 Matching stages

```text
Physical files
  → parse
  → group
  → generate provider queries
  → retrieve bounded candidates
  → deterministic score
  → expand top candidates
  → deterministic re-score
  → LLM verification according to policy
  → deterministic validation of LLM output
  → auto-confirm or queue review
```

### 12.2 Verification modes

Setting `llmVerificationMode`:

```text
off
ambiguousOnly
verifyAllNewGroups
```

Default for this product: `verifyAllNewGroups`, because the user explicitly wants LLM checking. The LLM verifies title-level matches for every new group. Episode-level LLM calls are reserved for ambiguity, conflicting ordering, translated title-only files, specials, suffix letters, and multi-episode anomalies.

### 12.3 Candidate-set rules

- Maximum ordinary title candidates supplied to the LLM: configurable, initially 8.
- Include only real provider candidates already fetched by application code.
- Include a stable `candidateKey` for each.
- Include enough metadata to differentiate remakes and similarly named works.
- Include candidate-specific season/episode evidence only for observed local seasons.
- Never ask the LLM to search the internet or invent a provider record.
- Never expose API credentials in the prompt.

### 12.4 Title scoring

Implement a deterministic score with an auditable breakdown. Scores are heuristics, not probabilities.

Suggested TV group components:

```text
+35 exact normalized primary-title match
+32 exact provider alias match
+20 high fuzzy title similarity
+15 exact first-air year match when local year exists
 -25 explicit year mismatch
+15 all observed seasons exist
+10 all explicit episode numbers are within candidate season bounds
+20 strong sample episode-title agreement
+10 folder and neighboring-file consistency
+ 5 duration distribution plausible for episodes
+ 5 media type agrees
 -40 strong title contradiction
 -30 observed season missing
 -25 multiple explicit episode-title contradictions
 -20 candidate is a movie when group is structurally TV
```

Suggested movie components:

```text
+55 exact normalized title match
+50 exact alias/localized-title match
+25 high fuzzy title similarity
+35 exact release year match
 -40 explicit release year mismatch
+10 media type agrees
+ 5 runtime plausibility when probed
+ 5 folder and filename agree
 -30 explicit TV structure present
```

Clamp only for display; retain raw breakdown for diagnostics.

### 12.5 Fuzzy similarity

Use a deterministic, tested string-similarity implementation. Compare:

- primary normalized title;
- article-stripped secondary key;
- diacritics-insensitive key;
- provider aliases;
- original provider name.

Do not use fuzzy similarity to override a strong explicit year or episode contradiction.

### 12.6 Episode title scoring

Normalize local and provider episode names similarly to title normalization but retain short words. Consider:

- exact normalized equality;
- token-set similarity;
- translated-title uncertainty;
- multi-title separators such as `&`, `/`, `and`;
- provider combined episodes;
- release tags removed from trailing text.

When a filename is translated and a season/episode marker is explicit and valid, lack of English-title similarity is neutral rather than negative.

### 12.7 Candidate acceptance policy

Do not auto-confirm based on one raw threshold alone.

A title may auto-confirm when all are true:

1. deterministic score is above the configured strong threshold;
2. score gap to second candidate exceeds the configured minimum;
3. there is no blocking contradiction;
4. required provider details were successfully fetched;
5. when LLM verification is enabled, the LLM selected the same candidate or explicitly returned a high-certainty match;
6. deterministic post-validation succeeds;
7. no manual rule or prior rejection conflicts.

Initial policy suggestion:

```text
strong threshold: 85
minimum lead over second candidate: 15
review threshold: 55
```

Tune against fixture and recorded match cases; store policy version.

### 12.8 Blocking contradictions

Examples:

```text
EXPLICIT_YEAR_MISMATCH
EXPLICIT_MEDIA_TYPE_MISMATCH
OBSERVED_SEASON_DOES_NOT_EXIST
EPISODE_NUMBERS_OUT_OF_RANGE
MULTIPLE_STRONG_EPISODE_TITLE_CONTRADICTIONS
MANUAL_REJECTION_EXISTS
TITLE_RULE_CONFLICT
CANDIDATE_REMOVED_OR_INVALID
```

### 12.9 File-to-title commit transaction

When confirming a group:

1. upsert canonical title, aliases, external IDs, and requested seasons/episodes;
2. create or update file-title links for eligible group members;
3. create episode links deterministically where explicit and valid;
4. queue ambiguous episode mapping work;
5. preserve manual links;
6. write match-attempt audit result;
7. enqueue artwork and watch-state recomputation;
8. commit atomically.

Do not leave half the group linked if the transaction fails.

### 12.10 Matching-rule application

Rules run before metadata search, ordered by priority and specificity:

```text
exactStorageKey
exact relative-path rule
folderPrefix
normalizedTitleAlias
validated filename regex
```

A rule proposes a canonical title. It still must pass basic invariant validation. User-confirmed exact rules can bypass LLM verification but remain auditable.

### 12.11 Rule creation from manual correction

After a user fixes a match, offer scopes:

```text
this file only
all files in this folder
files matching this parsed title
this season folder
```

Show a preview of affected files before creating a broad rule. Never create a broad rule silently.

---

<a id="section-13"></a>
## 13. LLM verification and prompts

### 13.1 LLM role

The LLM is a constrained adjudicator, not the catalog source. Application code obtains provider candidates. The LLM compares local evidence to those candidates and returns structured output.

The LLM must not:

- invent IDs;
- browse for metadata;
- issue provider requests;
- rename or alter files;
- write to the database directly;
- override manual decisions;
- determine final acceptance policy;
- receive unnecessary absolute paths;
- receive media content.

### 13.2 Provider abstraction

```dart
abstract interface class LlmMatchVerifier {
  Future<AppResult<TitleVerificationResult>> verifyTitle(
    TitleVerificationRequest request,
  );

  Future<AppResult<EpisodeVerificationResult>> verifyEpisodes(
    EpisodeVerificationRequest request,
  );
}
```

Implement a disabled/no-op adapter and one configured remote adapter. The OpenAI adapter should use the current Responses API or current recommended text-generation API with strict JSON Schema Structured Outputs. Keep model name configurable in secure settings or build configuration. Do not hardcode a model that may be retired.

### 13.3 Privacy preparation

Before an LLM request:

- replace absolute root paths with a logical root label;
- include only root-relative folders when needed;
- omit user account names and mount paths;
- omit unrelated filenames;
- strip provider API credentials;
- cap sample count;
- optionally strip release-group/site tokens after preserving relevant parsed evidence;
- compute and store a sanitized request hash;
- show the user a privacy disclosure before enabling remote LLM matching.

### 13.4 Prompt versioning

Every prompt has:

```text
prompt name
integer version
JSON schema version
matcher policy version
```

Persist these in match attempts. A prompt change does not automatically reprocess confirmed manual matches.

### 13.5 Title-verification system prompt

Use the following semantic prompt. Adapt API-specific formatting but preserve constraints.

```text
You are a deterministic media-catalog matching component.

You receive one local media group and a bounded list of real metadata candidates
already retrieved by the application. Select only from the supplied candidateKey
values. Never invent or alter a candidate key, provider ID, title, year, season,
episode, or external identifier.

Your job is to determine whether exactly one supplied candidate is supported by the
local evidence. If evidence is insufficient, contradictory, or split between multiple
candidates, return needs_review or unmatched as appropriate.

Use evidence in this priority order:
1. Explicit season and episode compatibility.
2. Episode-title compatibility, including multi-episode filenames.
3. Exact release/first-air year compatibility.
4. Exact normalized title or supplied alternative-title compatibility.
5. Localized, translated, accented, or unaccented title compatibility.
6. Consistency across neighboring files and parent folders.
7. Runtime and media-type plausibility.

Release information such as resolution, codec, source, audio format, HDR format,
release group, and download-site tokens is not title identity evidence.

A top-level folder named Movies or TV Shows is weak evidence only. A movie may be
stored in TV Shows and vice versa.

Local episode titles can be translated. Do not call a translated title a contradiction
when explicit season/episode identifiers are otherwise valid.

Some shows have segment-level, combined-broadcast, DVD, or streaming orderings.
Do not force a numeric match when supplied episode titles show a different ordering.

Return only JSON conforming to the supplied schema. Do not include prose outside JSON.
```

### 13.6 Title-verification request shape

```json
{
  "schemaVersion": 1,
  "group": {
    "groupKey": "opaque-local-key",
    "probableMediaKind": "tv",
    "folderLabels": [
      "Spongebob Squarepants Season 5 Complete WEB x264 [i_c]"
    ],
    "titleCandidates": [
      "SpongeBob SquarePants"
    ],
    "yearCandidates": [],
    "observedSeasons": [5],
    "observedEpisodeRange": {
      "season": 5,
      "minimum": 1,
      "maximum": 39
    },
    "sampleFiles": [
      {
        "localFileKey": "f1",
        "fileName": "SpongeBob SquarePants S05E01 Friend or Foe.mkv",
        "parsedSeason": 5,
        "parsedEpisodes": [1],
        "parsedEpisodeTitle": "Friend or Foe",
        "parseReasonCodes": ["EXPLICIT_SXXEXX"]
      }
    ],
    "anomalies": [
      {
        "localFileKey": "f-special",
        "fileName": "SpongeBob SquarePants Special 5-0 Atlantis Squarepantis.mkv",
        "parsedSeason": null,
        "parsedEpisodes": [],
        "parsedEpisodeTitle": "Atlantis Squarepantis",
        "parseReasonCodes": ["SPECIAL_TEXT_PRESENT"]
      }
    ]
  },
  "candidates": [
    {
      "candidateKey": "candidate-1",
      "provider": "tmdb",
      "providerId": "387",
      "mediaKind": "tv",
      "name": "SpongeBob SquarePants",
      "originalName": "SpongeBob SquarePants",
      "firstAirYear": 1999,
      "alternativeTitles": [],
      "observedSeasonEvidence": [
        {
          "seasonNumber": 5,
          "exists": true,
          "episodeCount": 39,
          "sampleEpisodes": [
            {"episodeNumber": 1, "name": "Friend or Foe"}
          ]
        }
      ],
      "deterministicScore": 98,
      "deterministicReasonCodes": [
        "TITLE_EXACT",
        "SEASON_EXISTS",
        "EPISODE_TITLE_EXACT"
      ],
      "contradictionCodes": []
    }
  ]
}
```

The example provider values are illustrative; production input contains current provider data fetched by code.

### 13.7 Title-verification output schema

Use strict JSON schema equivalent to:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion",
    "decision",
    "selectedCandidateKey",
    "confidenceLabel",
    "reasonCodes",
    "evidence",
    "conflicts",
    "warnings"
  ],
  "properties": {
    "schemaVersion": {"const": 1},
    "decision": {
      "type": "string",
      "enum": ["match", "needs_review", "unmatched"]
    },
    "selectedCandidateKey": {
      "type": ["string", "null"]
    },
    "confidenceLabel": {
      "type": "string",
      "enum": ["very_high", "high", "medium", "low"]
    },
    "reasonCodes": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "TITLE_EXACT",
          "TITLE_ALIAS_EXACT",
          "TITLE_FUZZY",
          "LOCALIZED_TITLE_COMPATIBLE",
          "YEAR_EXACT",
          "YEAR_CONFLICT",
          "MEDIA_KIND_COMPATIBLE",
          "MEDIA_KIND_CONFLICT",
          "SEASON_COMPATIBLE",
          "SEASON_CONFLICT",
          "EPISODE_NUMBER_COMPATIBLE",
          "EPISODE_TITLE_COMPATIBLE",
          "EPISODE_TITLE_CONFLICT",
          "FOLDER_CONTEXT_COMPATIBLE",
          "MULTI_EPISODE_COMPATIBLE",
          "ORDERING_AMBIGUOUS",
          "INSUFFICIENT_EVIDENCE",
          "MULTIPLE_CANDIDATES_PLAUSIBLE"
        ]
      },
      "uniqueItems": true
    },
    "evidence": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "localValue", "candidateValue", "assessment"],
        "properties": {
          "kind": {
            "type": "string",
            "enum": [
              "title",
              "alias",
              "year",
              "media_kind",
              "season",
              "episode_number",
              "episode_title",
              "folder_context",
              "ordering"
            ]
          },
          "localValue": {"type": ["string", "null"]},
          "candidateValue": {"type": ["string", "null"]},
          "assessment": {
            "type": "string",
            "enum": ["supports", "neutral", "conflicts"]
          }
        }
      }
    },
    "conflicts": {
      "type": "array",
      "items": {"type": "string"}
    },
    "warnings": {
      "type": "array",
      "items": {"type": "string"}
    }
  }
}
```

Post-validation rules:

- `decision=match` requires non-null `selectedCandidateKey`.
- other decisions require null candidate unless schema policy explicitly permits a review suggestion.
- selected key must exist in supplied candidates.
- no result can introduce provider IDs or episode IDs.
- model confidence is advisory only.

### 13.8 Episode-verification system prompt

```text
You are matching local video files to canonical television episodes for a title that
has already been selected by the application.

You may select only canonicalEpisodeKey values supplied in the input. Never invent an
episode, season, key, title, or provider ID.

A local file may map to one episode, multiple episodes, or no episode. Multiple local
files may map to the same canonical episode because the library may contain different
languages, releases, resolutions, or segment files.

Prefer explicit season/episode tokens when compatible with the supplied canonical
list. Compare episode titles when numbering may use a different ordering. Recognize
S01E02, S01E02E03, S01E02-E03, 1x02, natural-language Season/Episode forms, specials,
and suffixes such as S06E11b.

Local titles may be translated. A translated title is not a contradiction by itself.
Codec, resolution, source, audio, HDR, release-group, and site tokens are not identity
evidence.

If a combined file contains multiple supplied canonical episodes, return all of them
in playback order. If exact segment boundaries are not supplied, do not invent them.

Return only JSON conforming to the supplied schema.
```

### 13.9 Episode-verification request shape

```json
{
  "schemaVersion": 1,
  "title": {
    "provider": "tmdb",
    "providerId": "387",
    "name": "SpongeBob SquarePants",
    "orderingKey": "default"
  },
  "canonicalEpisodes": [
    {
      "canonicalEpisodeKey": "ep-1",
      "seasonNumber": 1,
      "episodeNumber": 1,
      "segmentCode": null,
      "name": "Help Wanted",
      "alternativeNames": []
    },
    {
      "canonicalEpisodeKey": "ep-2",
      "seasonNumber": 1,
      "episodeNumber": 2,
      "segmentCode": null,
      "name": "Reef Blower",
      "alternativeNames": []
    },
    {
      "canonicalEpisodeKey": "ep-3",
      "seasonNumber": 1,
      "episodeNumber": 3,
      "segmentCode": null,
      "name": "Tea at the Treedome",
      "alternativeNames": []
    }
  ],
  "localFiles": [
    {
      "localFileKey": "file-123",
      "fileName": "SpongeBob SquarePants (1999) - S01E01-E03 - Help Wanted & Reef Blower & Tea at the Treedome.mkv",
      "parsedSeason": 1,
      "parsedEpisodes": [1, 2, 3],
      "parsedEpisodeSuffix": null,
      "parsedEpisodeTitle": "Help Wanted & Reef Blower & Tea at the Treedome",
      "durationMs": null
    }
  ]
}
```

### 13.10 Episode-verification output schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "mappings"],
  "properties": {
    "schemaVersion": {"const": 1},
    "mappings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "localFileKey",
          "decision",
          "canonicalEpisodeKeys",
          "confidenceLabel",
          "reasonCodes",
          "warnings"
        ],
        "properties": {
          "localFileKey": {"type": "string"},
          "decision": {
            "type": "string",
            "enum": ["match", "needs_review", "unmatched"]
          },
          "canonicalEpisodeKeys": {
            "type": "array",
            "items": {"type": "string"},
            "uniqueItems": true
          },
          "confidenceLabel": {
            "type": "string",
            "enum": ["very_high", "high", "medium", "low"]
          },
          "reasonCodes": {
            "type": "array",
            "items": {
              "type": "string",
              "enum": [
                "EXPLICIT_SINGLE_EPISODE",
                "EXPLICIT_CHAINED_EPISODES",
                "EXPLICIT_EPISODE_RANGE",
                "EXPLICIT_NXNN",
                "NATURAL_LANGUAGE_EPISODE",
                "EPISODE_TITLE_EXACT",
                "EPISODE_TITLE_FUZZY",
                "TRANSLATED_TITLE_POSSIBLE",
                "SPECIAL_MATCH",
                "SUFFIX_PART_MATCH",
                "ORDERING_CONFLICT",
                "NUMBER_OUT_OF_RANGE",
                "TITLE_CONFLICT",
                "INSUFFICIENT_EVIDENCE"
              ]
            },
            "uniqueItems": true
          },
          "warnings": {
            "type": "array",
            "items": {"type": "string"}
          }
        }
      }
    }
  }
}
```

Post-validation:

- every `localFileKey` must exist in the request exactly once;
- every returned episode key must exist in the supplied canonical list;
- returned episodes must belong to the selected title;
- `match` requires at least one episode key;
- `unmatched` requires no episode keys;
- order must be canonical playback order unless explicit local title order proves otherwise;
- code, not the LLM, creates database links.

### 13.11 LLM retries

Retry only for:

- network timeout;
- transient provider error;
- rate limit according to backoff policy;
- output transport failure.

For strict structured outputs, a schema-invalid response is a provider/implementation failure, not an invitation to silently parse prose. Record it and either retry once with the same versioned request or queue review according to policy.

### 13.12 LLM caching and idempotency

Compute `inputHash` from canonical sanitized JSON including:

- prompt version;
- schema version;
- local group evidence;
- candidate records and deterministic scores;
- configured model key.

Reuse a successful prior result for the same hash. Do not pay for identical verification repeatedly.

Invalidate when relevant evidence or prompt version changes.

### 13.13 Cost controls

Settings must support:

```text
LLM disabled
verification mode
maximum calls per scan
maximum calls per day
maximum candidate count
maximum sample files
model identifier
```

Display usage diagnostics without implying exact billing unless the provider supplies exact usage. Store token counts and estimated micro-cost when available.

### 13.14 LLM acceptance tests

Use a fake LLM adapter in deterministic tests. Add contract tests for the remote adapter behind an opt-in environment flag and never require real paid API access in normal CI.

Test cases:

- exact single candidate;
- ambiguous remake with same title;
- wrong year;
- movie under TV folder;
- localized Peppa/Prasiatko alias;
- chained Octonauts episodes;
- SpongeBob range;
- suffix `E11b`;
- special with no number;
- invented candidate key rejection;
- missing required field rejection;
- manual match protected from reprocessing;
- identical input uses cached result.

---

<a id="section-14"></a>
## 14. Media probing and thumbnails

### 14.1 Probe abstraction

```dart
abstract interface class MediaProbe {
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryFileRef file,
    required ProbeOptions options,
    required CancellationToken cancellationToken,
  });
}
```

`MediaProbeResult` includes:

```text
durationMs
container format
video dimensions
rotation
frame rate
video codec
bit depth
HDR hint
audio streams
subtitle streams
chapters
raw diagnostic summary
```

### 14.2 Android probe implementation

Prefer a small custom native Android implementation based on maintained platform APIs when they provide enough data:

- `MediaMetadataRetriever` for duration, dimensions, rotation, and thumbnail frame;
- `MediaExtractor` for track enumeration, MIME/codec hints, language, channels, sample rate, and duration where exposed;
- `ContentResolver`/file descriptor access for SAF URIs.

Benefits:

- no second full FFmpeg distribution solely for metadata;
- direct content-URI support;
- smaller binary and simpler licensing surface.

If these APIs cannot reliably probe important MKV/codec cases on the target tablets, implement another adapter behind the same interface. Do not bind domain code to the replacement.

### 14.3 Probe policy

Probe:

- every stable new video;
- changed videos whose fingerprint no longer matches the stored probe;
- files explicitly retried by the user;
- files requiring duration/stream evidence for matching.

Do not probe:

- resource forks;
- sidecars;
- missing files;
- unstable/in-progress copies;
- unchanged files with a current successful probe.

### 14.4 Probe concurrency

Default concurrency on Android tablet: 1. Increase only after benchmarks. Probing many large videos in parallel can exhaust descriptors, saturate storage, heat the device, and delay playback.

Playback has priority over background probing. Pause or reduce background probe work while video is playing.

### 14.5 Unsupported versus failed

Distinguish:

```text
unsupported: format/codec cannot be interpreted by probe implementation
failed: expected-capable operation failed due to IO, corruption, permission, or transient error
```

A probe failure does not automatically mean playback will fail. Permit “try playback” and record actual player result.

### 14.6 Thumbnail generation

Generate thumbnails lazily. Priority:

1. title artwork from provider/local artwork;
2. episode still from provider;
3. generated file frame only when useful or metadata artwork is absent.

For generated frames:

- choose a timestamp away from black opening frames, initially around 10% or a bounded number of seconds;
- retry another timestamp if extraction returns an unusable frame where detectable;
- generate bounded dimensions appropriate to UI;
- write atomically to cache;
- include file fingerprint and thumbnail algorithm version in cache key;
- rate-limit generation;
- delete stale cache entries through bounded eviction.

Do not generate hundreds of thumbnails during initial scan before the catalog is usable.

### 14.7 Chapter handling

If chapters exist:

- persist chapter index, start/end, and title in an extension table or probe JSON;
- attempt to map chapter titles to canonical episodes in multi-episode files;
- never infer segment boundaries without evidence;
- expose chapter navigation in player only when available.

---

<a id="section-15"></a>
## 15. Playback architecture

### 15.1 Player engine

Use `media_kit` as the initial playback engine, subject to the Milestone 0 compatibility spike and current maintenance verification. Wrap it behind `PlaybackEngine`.

```dart
abstract interface class PlaybackEngine {
  Stream<PlaybackEvent> get events;
  PlaybackSnapshot get current;

  Future<AppResult<void>> initialize();
  Future<AppResult<void>> open(PlaybackRequest request);
  Future<AppResult<void>> play();
  Future<AppResult<void>> pause();
  Future<AppResult<void>> seek(Duration position);
  Future<AppResult<void>> setVolume(double volume);
  Future<AppResult<void>> setRate(double rate);
  Future<AppResult<void>> selectAudioTrack(String trackKey);
  Future<AppResult<void>> selectSubtitleTrack(String? trackKey);
  Future<AppResult<void>> stop();
  Future<void> dispose();
}
```

The rest of the application must not import `media_kit` types.

### 15.2 Playback request

```dart
final class PlaybackRequest {
  const PlaybackRequest({
    required this.file,
    required this.sourceLease,
    required this.resumePosition,
    required this.externalSubtitles,
    required this.preferredAudioLanguages,
    required this.preferredSubtitleLanguages,
    required this.autoplay,
    required this.queueContext,
  });
}
```

### 15.3 Player lifecycle

1. Resolve selected physical version.
2. Validate root and file availability.
3. Acquire playback source lease.
4. Initialize/open player.
5. Wait for duration/tracks or a bounded timeout.
6. Select preferred audio/subtitle tracks.
7. Seek to valid resume position.
8. Begin playback.
9. Persist progress periodically and on lifecycle events.
10. On stop/navigation/dispose, persist final state, close player, and release lease.

Always release native resources in `finally` paths.

### 15.4 Preferred physical version

One canonical movie or episode may have multiple files. Rank available versions using a deterministic score:

```text
manual profile preference
preferred language/audio availability
successful prior playback
resolution appropriate to device
video codec hardware compatibility
HDR compatibility
audio compatibility
non-corrupt successful probe
higher quality only after compatibility
stable local availability
```

Do not blindly pick the largest or highest-resolution file. A compatible 1080p file may be preferable to unsupported 4K HEVC/HDR on an older tablet.

Show “Other versions” on detail pages and allow manual preference.

### 15.5 Track selection

Selection order:

1. previously selected language/track for this file/profile;
2. user preferred language order;
3. stream flagged default;
4. player automatic choice;
5. first compatible track.

For subtitles:

- respect explicit user last choice;
- support `off`;
- prefer forced tracks when audio language differs from preferred language, according to settings;
- attach external sidecars;
- read small SRT/VTT sidecars into memory if content URI cannot be passed directly;
- preserve subtitle style settings.

### 15.6 Player UI requirements

Controls:

- play/pause;
- seek bar with elapsed and remaining/total time;
- 10-second rewind and forward;
- next episode when applicable;
- previous episode when applicable;
- audio track selector;
- subtitle selector and off option;
- playback speed;
- fullscreen/immersive mode;
- orientation behavior;
- title and episode label;
- back/close;
- optional chapter control;
- error/retry panel.

Tablet interaction:

- large touch targets;
- controls hide after inactivity and reappear on tap;
- hardware keyboard/media buttons supported where practical;
- back button first exits control overlays/fullscreen as appropriate, then player;
- do not make critical actions gesture-only.

### 15.7 Progress persistence cadence

Do not write every position event.

Persist when any occurs:

- at most every configurable interval, initially 10 seconds, while position changes;
- pause;
- seek completion;
- app moves to background/inactive;
- player route closes;
- playback ends;
- media changes in queue;
- fatal player error.

Maintain latest position in memory so UI remains smooth.

### 15.8 Watched semantics

A file is considered watched when either:

```text
position / duration >= configured percentage, initially 0.92
```

or:

```text
remaining duration <= configured maximum, initially 120 seconds for movies
and a smaller bounded value for short episodes
```

Use a duration-aware threshold so a 7-minute children’s episode is not marked watched two minutes early.

Suggested function:

```text
remainingThreshold = min(configuredMaximum, max(configuredMinimum, duration * 0.05))
watched = ratio >= percentageThreshold OR remaining <= remainingThreshold
```

Tune and test. Manual “Mark watched/unwatched” always overrides derived status until the user resumes playback or explicitly clears the override according to documented behavior.

### 15.9 Movie progress

Movie card state:

```text
unwatched: no meaningful playback
in progress: resume position > minimum and not watched
watched: completed/manual watched
```

If multiple files map to one movie, select the most recent meaningful playback state for Continue Watching and retain per-file states.

### 15.10 TV episode watch state

For a single-episode file:

- file progress maps directly to episode watch state.

For a multi-episode file with known segment boundaries:

- derive episode progress from the active segment.

For a multi-episode file without boundaries:

- show one file-level progress bar labeled with the episode range;
- do not claim an exact current episode segment;
- mark all linked episodes watched only when the whole file completes or the user explicitly marks them;
- optionally mark the first linked episode in progress for “Continue Watching,” with a warning internally that segment is unknown.

### 15.11 Resume episode and next episode

These are separate concepts.

**Resume item:** Most recently played incomplete file for the title.

**Next episode:** First unwatched locally available canonical episode after the highest contiguous watched episode in the selected ordering, subject to settings.

Algorithm must handle:

- out-of-order watched episodes;
- missing local episodes;
- specials;
- multi-episode files;
- multiple physical versions;
- unavailable roots.

Default missing-episode behavior:

- do not auto-skip silently in progress calculation;
- “Play next available” may skip a missing episode but label the skipped gap;
- user can configure whether specials participate in ordering/progress.

### 15.12 Title progress

Show two separate metrics where useful:

```text
Watch progress: watched locally available canonical episodes / locally available canonical episodes
Library availability: locally available canonical episodes / all canonical episodes in selected ordering
```

Do not conflate them.

Top-level card may display:

```text
S2 · E17 next
74% watched
```

The title-detail page shows full counts.

### 15.13 Autoplay next

When enabled:

1. determine next locally available episode;
2. display countdown and next title;
3. allow cancel;
4. acquire new playback lease before releasing current only when resource limits permit;
5. persist completed state;
6. open next file and update route/player context.

Do not autoplay across different titles.

### 15.14 Playback errors

Classify and surface:

```text
FILE_MISSING
ROOT_UNAVAILABLE
PERMISSION_REVOKED
UNSUPPORTED_CONTAINER
UNSUPPORTED_VIDEO_CODEC
UNSUPPORTED_AUDIO_CODEC
SOURCE_OPEN_FAILED
DECODER_INITIALIZATION_FAILED
SEEK_FAILED
EXTERNAL_SUBTITLE_FAILED
CORRUPT_MEDIA
UNKNOWN_PLAYER_ERROR
```

Offer meaningful actions:

- retry;
- choose another version;
- rescan root;
- repair permission;
- open diagnostics;
- mark version as incompatible on this device.

### 15.15 Device capability history

Record playback success/failure by coarse codec/profile/resolution/HDR attributes, without tracking private content externally. Use it to improve version selection on that device.

Do not permanently blacklist a codec from one transient failure. Require repeated consistent evidence or user selection.

---

<a id="section-16"></a>
## 16. Application services and state management

### 16.1 Riverpod usage

Use Riverpod for dependency composition and reactive application state. Prefer generated providers if current Riverpod code generation is stable and adopted consistently.

Riverpod is not the domain model. Providers coordinate repositories and use cases.

### 16.2 Provider categories

Long-lived dependencies:

```text
clockProvider
databaseProvider
libraryRepositoryProvider
scanRepositoryProvider
metadataProviderProvider
llmVerifierProvider
playbackEngineProvider
credentialStoreProvider
loggerProvider
jobRunnerProvider
```

Reactive query providers:

```text
homeCatalogProvider(profileId)
titleDetailProvider(titleId, profileId)
seasonEpisodesProvider(titleId, seasonNumber, profileId)
continueWatchingProvider(profileId)
needsAttentionProvider
scanStatusProvider(rootId)
rootHealthProvider
```

Command/controller providers:

```text
onboardingControllerProvider
libraryScanControllerProvider
matchReviewControllerProvider
playerControllerProvider
settingsControllerProvider
```

### 16.3 Provider lifetime

- Infrastructure singletons and database are keep-alive.
- Screen-specific queries may auto-dispose when cheap to recreate.
- Active playback controller remains alive for the player route/session.
- Scan/job coordinator remains alive while work exists.
- Do not accidentally start duplicate scans or duplicate player instances due to provider rebuilds.

### 16.4 Use cases

Create explicit use cases such as:

```text
AuthorizeLibraryRoot
StartLibraryScan
CancelLibraryScan
RetryFailedJob
SearchAndResolveLocalGroup
ConfirmTitleMatch
RejectTitleMatch
ConfirmEpisodeMappings
CreateMatchingRule
RemoveMatchingRule
RefreshTitleMetadata
SelectPreferredMediaVersion
StartPlayback
UpdatePlaybackProgress
MarkEpisodeWatched
MarkTitleWatched
RepairRootPermission
ExportDiagnostics
```

Each use case should have one clear transaction/application boundary and typed result.

### 16.5 Job runner

Implement an in-process persistent job runner for MVP.

Requirements:

- reads pending jobs ordered by priority and ready time;
- uses per-job-type concurrency limits;
- claims jobs atomically;
- updates heartbeat for long tasks;
- recovers jobs left running after process termination;
- retries retryable failures with exponential backoff and jitter;
- dead-letters after maximum attempts;
- deduplicates by `(type, dedupeKey)`;
- supports cancellation by root/scan/file where safe;
- yields to playback and foreground UI;
- exposes aggregate status to UI.

Suggested priorities:

```text
highest: user-requested playback validation, permission repair
high: parse, title matching for visible new files
normal: provider enrichment, episode mapping
low: thumbnail generation, stale metadata refresh
```

### 16.6 Concurrency limits

Initial conservative defaults:

```text
storage enumeration: 1 per root, at most 1–2 global
DB reconciliation: serialized per root
parser: small isolate pool or synchronous batch if cheap
probe: 1 Android tablet
metadata HTTP: 3
LLM: 1
thumbnail: 1
```

Measure before increasing.

### 16.7 Cancellation

Use a shared cancellation abstraction through application and infrastructure layers. Cancellation is not an error in user-facing diagnostics.

A cancelled scan:

- stops enumeration and new job scheduling;
- commits already safe upserts;
- never marks unseen files missing;
- leaves resumable derived jobs only if their source files remain valid;
- records cancelled state.

---

<a id="section-17"></a>
## 17. Presentation architecture and UX contract

The presentation layer must make the physical filesystem disappear during normal use while retaining a diagnostics path for users who need to inspect or repair mappings. The primary UX vocabulary is titles, seasons, episodes, availability, progress, and versions—not folders and filenames.

### 17.1 Presentation principles

1. **Catalog first.** The home experience presents canonical movies and shows.
2. **Local truth is visible.** Never imply that an episode is playable when no currently available file is linked.
3. **Metadata failure must not block playback.** Unmatched files remain accessible in the Needs Attention area and can be played directly.
4. **No dead-end states.** Every error state provides a concrete recovery action.
5. **Progress semantics are consistent.** The same resume/completion logic is used on cards, details, search results, and the player.
6. **Remote-control and touch friendly.** Minimum interactive target size is 48 logical pixels. Focus traversal must be deterministic even before TV-platform support is added.
7. **Landscape tablet is the primary composition.** Portrait and desktop remain usable, but do not compromise the landscape tablet layout to mimic a phone app.
8. **Do not copy Netflix branding or proprietary visual assets.** The experience may use familiar content rows and cinematic details, but the visual identity must be original.
9. **Never expose raw exceptions.** Present a user-readable summary plus a copyable diagnostic identifier.
10. **Avoid blocking modal dialogs for background work.** Scans, matching, and enrichment continue without trapping the user.

### 17.2 Shared visual language

Define semantic design tokens rather than ad hoc widget values:

```dart
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadii {
  static const double small = 6;
  static const double medium = 10;
  static const double large = 16;
}
```

Use Material 3 as a foundation but define a dedicated `AppTheme` layer. Components must not read arbitrary colors directly. Use `ColorScheme`, semantic extensions, and typography styles.

Required semantic colors/states:

- available/playable;
- missing;
- watched;
- partially watched;
- unmatched/attention;
- offline root;
- warning;
- destructive;
- focus indicator.

Do not encode state using color alone. Pair colors with icons, text, progress marks, or patterns.

### 17.3 Responsive breakpoints

Use layout classes, not device-name checks:

```text
compact: width < 600
medium: 600 <= width < 1024
expanded: width >= 1024
```

Primary target:

```text
Samsung-style Android tablet
landscape
approximately 1280–2560 logical/physical pixel combinations
```

Rules:

- Compact: single-column details, bottom navigation, two-to-three poster columns.
- Medium: navigation rail or compact top navigation, three-to-five poster columns.
- Expanded: navigation rail, hero/details split layouts, five-plus poster columns.
- Respect display cutouts and system insets.
- Never hardcode exact device pixel dimensions.
- Use `LayoutBuilder`, `MediaQuery`, and shared breakpoint helpers.

### 17.4 Application shell

The shell owns:

- root router outlet;
- navigation rail/bottom bar;
- global search entry;
- profile selector placeholder;
- scan status indicator;
- transient snackbar/notification host;
- global loading overlay only for startup-critical initialization;
- keyboard and remote-control shortcut handling.

Primary destinations:

```text
Home
Movies
TV Shows
Search
Needs Attention
Settings
```

On compact layouts, keep the first four in bottom navigation and place the remaining destinations in an overflow/settings menu. On expanded layouts, use a rail.

The shell must remain mounted while navigating between catalog screens so that scan status, player mini-state in future versions, and navigation focus are preserved.

### 17.5 Startup state machine

The initial app surface must distinguish:

```text
Bootstrapping database
Checking storage grants
No library configured
Library permission lost
Catalog available, background work continuing
Fatal local database failure
```

Expected behavior:

1. Open database and run migrations.
2. Load persisted settings and profile.
3. Validate library roots without recursively scanning.
4. Render cached catalog immediately when possible.
5. Start due reconciliation/enrichment jobs after the shell appears.
6. Never show an empty home screen solely because TMDB or the LLM provider is offline.

### 17.6 Onboarding and first-run library setup

#### Screen: Welcome

Purpose: explain that the app organizes and plays files already stored on the device.

Required actions:

- `Choose media folder`
- optional `Open demo catalog` only if a deterministic bundled demo fixture is implemented;
- link to privacy explanation;
- do not ask for TMDB or LLM credentials before the user sees local files discovered.

#### Screen: Choose folder

On Android, launch the system directory picker. After a grant is returned:

- display the provider-supplied display name;
- display whether persistent access was successfully obtained;
- let the user assign an optional friendly name;
- do not require the user to classify it as Movies or TV because the real fixture demonstrates mixed placement;
- default to including subfolders;
- allow cancel without corrupting onboarding state.

#### Screen: Initial scan

Show phase-level progress rather than fake byte percentages:

```text
Discovering files… 583 found
Indexing media… 420 / 583
Identifying titles… 12 / 19 groups
Downloading artwork… 7 / 12
```

Required controls:

- `Continue in background` after enough content exists to render the catalog;
- `Cancel scan` with documented cancellation semantics;
- `View details` to open the scan diagnostics panel.

On completion, summarize:

```text
1,088 playable video files
7 identified titles
N files need attention
54 subtitle files linked or awaiting linkage
```

Counts must come from actual scan results; these example numbers mirror the development fixture and are not hardcoded.

### 17.7 Home screen

The home screen is derived from repository queries, never assembled from raw filesystem traversal.

Required sections, conditionally rendered:

1. **Continue Watching**
   - partially watched movie files;
   - partially watched TV episodes;
   - most recently played first;
   - hide items completed beyond the completion threshold unless replayed;
   - card shows normalized title, episode context when relevant, and file-position progress.

2. **Next Episodes**
   - one recommendation per active TV title/profile;
   - based on canonical order and local availability;
   - do not skip a missing episode silently; show `Next available` wording when canonical next is unavailable.

3. **Recently Added**
   - titles whose first available local file was discovered most recently;
   - adding a second version to an existing title should not necessarily move it to the front unless product policy explicitly changes.

4. **Movies**
   - locally available movies;
   - sorted by configurable default, initially title name or recently added.

5. **TV Shows**
   - locally available shows;
   - include season/episode availability summary.

6. **Needs Attention**
   - only when actionable items exist;
   - show count and a small representative set;
   - do not expose internal confidence decimals on the home card.

Each content row must support:

- horizontal scrolling;
- keyboard/remote focus;
- semantic labels;
- deterministic stable keys;
- skeleton loading only when no cached row data exists;
- empty-state suppression rather than rendering empty carousels.

### 17.8 Title cards

#### Movie card

Displays:

- poster or generated fallback;
- title;
- year when useful for disambiguation;
- playback progress line if started;
- unavailable-root badge if its preferred file cannot currently be opened;
- optional quality badge only in details, not by default on the home screen.

Primary tap opens movie details. A prominent resume/play overlay may be enabled only after usability testing; avoid accidental playback from card taps in the first implementation.

#### TV card

Displays:

- poster;
- title;
- progress summary such as `Season 2 · Episode 18` or `187 of 241 watched`;
- availability summary such as `3 seasons available`;
- partial progress bar computed from locally available canonical episodes, with accessible text explaining the denominator;
- attention badge only when unresolved files plausibly belong to this title.

#### Fallback artwork

Generate a deterministic visual from:

- title initials;
- media type icon;
- hash-derived neutral gradient or palette selected from approved theme tokens;
- no random changes between launches.

### 17.9 Movies screen

Required controls:

- search/filter field scoped to movies;
- sort: title, year, recently added, recently played, unwatched;
- availability filter;
- watched-state filter;
- grid/list adaptive layout;
- item count;
- pull-to-refresh may request reconciliation but must not imply network-only refresh.

The query should be paged or virtualized if the catalog grows. Do not load all artwork bytes into memory simultaneously.

### 17.10 TV Shows screen

Required controls:

- search/filter field scoped to shows;
- sort: title, recently added, recently played, completion;
- availability filter;
- grid/list adaptive layout;
- badges for missing seasons only when the user opts into completeness display.

A show with no successfully mapped canonical episodes but a confident title match remains visible and links to a details screen that explains the mapping state.

### 17.11 Global search

Search across:

- canonical title names;
- alternative/localized aliases;
- movie years;
- canonical episode names;
- locally parsed episode titles;
- optionally filenames only under an explicit `Include technical file names` toggle or diagnostics mode.

Search behavior:

- debounce textual input by approximately 200–300 ms;
- use SQLite FTS if justified by scale; otherwise start with normalized indexed columns and measure;
- ignore punctuation and diacritic differences for discovery, while preserving original display text;
- group results into Movies, TV Shows, Episodes, and Unmatched Files;
- episode result opens the parent show and focuses/highlights the episode;
- support empty query with recent searches only if persisted privately and clearable.

### 17.12 Movie details screen

Layout:

- backdrop/hero area where available;
- poster;
- canonical title, year, runtime, genres if cached;
- synopsis;
- prominent Play/Resume button;
- progress and last-played information;
- local version selector;
- technical details expandable panel;
- metadata/match correction action in overflow menu.

Version selector must expose each available `MediaFile` linked to the movie, including:

```text
resolution
video codec
HDR indicator
audio language/codec summary
container
file availability
relative location only in diagnostics mode
```

Preferred version ordering is deterministic and configurable. Initial default:

1. user-pinned preferred file;
2. currently available file;
3. supported codec confidence;
4. preferred audio language;
5. higher resolution, subject to device capability;
6. higher quality/source ranking if known;
7. stable ID tie-breaker.

Actions:

- Play/Resume;
- Play from beginning;
- Mark watched/unwatched;
- Choose version;
- Fix match;
- Refresh metadata;
- Show file details;
- Remove from library is not a physical delete in MVP—provide `Ignore file` with explicit wording.

### 17.13 TV show details screen

Header displays:

- backdrop/poster;
- title and first-air year;
- synopsis and status if cached;
- local availability summary;
- watch-progress summary;
- `Resume` or `Play next` primary action;
- metadata source attribution where required.

Below the header:

- season selector/dropdown or horizontal chips;
- optional `All`, `Specials`, and regular seasons;
- season availability indicator, e.g. `48 / 52 local`;
- canonical episode count and local mapped count must not be conflated;
- an explicit explanation is available via tooltip/info action.

#### Season list behavior

Canonical seasons from the provider define the complete picture. Locally mapped files decorate those episodes.

For each season:

```text
Season 1
52 canonical episodes
52 locally available
49 watched
```

If a metadata provider includes an unaired season or specials, represent it accurately and allow filtering. Do not imply a missing local file is a scanner failure.

#### Episode row/card

Display:

- episode number;
- canonical name;
- optional thumbnail/still;
- runtime;
- availability icon/state;
- watch state and progress;
- air date when useful;
- multiple-version indicator;
- warning when linked via an ambiguous or manually reviewed mapping.

Required states:

```text
available_unwatched
available_in_progress
available_watched
missing_local_file
unavailable_root
metadata_only_unaired
mapping_warning
```

Actions:

- play/resume;
- play from beginning;
- mark watched/unwatched;
- select version;
- inspect/fix mapping;
- reveal technical details.

Do not render one physical multi-episode file as though each episode had independent seek boundaries unless segment boundaries are known. For a file mapped to episodes 1–3, all three episode rows may launch the same file; display a `Combined file` badge. The first MVP may resume the shared file position globally. The UI must not fabricate per-episode offsets.

### 17.14 Needs Attention dashboard

This is a first-class product surface, not a hidden debug screen.

Tabs/filters:

```text
Unmatched groups
Ambiguous title matches
Ambiguous episode mappings
Missing permissions
Unreadable/unsupported files
Duplicate candidates
Metadata errors
Ignored
```

Each item displays:

- human-readable inferred title;
- representative poster/fallback;
- number of files affected;
- reason summary;
- strongest evidence;
- recommended action;
- last attempt timestamp;
- retry state.

Do not display the full LLM reasoning chain. Display concise stored evidence/reason codes and candidate comparison data.

### 17.15 Fix Match workflow

The workflow must support title-level and episode-level repair.

#### Step A: inspect local evidence

Show:

- folder/group display name;
- representative filenames;
- parsed hints;
- languages and years inferred;
- season/episode coverage;
- file count;
- existing candidate scores;
- warnings such as multi-episode ranges or localized names.

Raw paths must be collapsed by default and revealed only on request.

#### Step B: select entity type

Options:

```text
Movie
TV show
Ignore this group
Split group
```

`Split group` allows users to assign subsets of files when grouping was wrong. The MVP implementation can use simple multi-select rather than a complex visual rule builder.

#### Step C: search metadata provider

Search results display:

- title;
- year;
- poster;
- media type;
- provider;
- original title;
- distinguishing synopsis snippet;
- confidence/evidence summary when generated by the matcher.

The user may alter the search query. Search never silently commits.

#### Step D: confirm scope

Options:

- this file only;
- selected files;
- this inferred group;
- this folder and subfolders;
- future files matching a generated rule.

Before creating a broad rule, preview affected files and present the normalized rule conditions.

#### Step E: episode mapping for TV

After selecting a show:

- fetch/cache canonical seasons and episodes;
- prefill mappings from deterministic parser and LLM verification;
- display unresolved/conflicting mappings;
- permit mapping one file to one or many episodes;
- permit one episode to have many files;
- permit `unmapped extra`;
- support translated episode titles without requiring title equality;
- warn before assigning an episode already linked to the same physical fingerprint.

#### Step F: persist correction

Persist:

- direct links;
- source=`manual`;
- user-confirmed confidence semantics;
- optional reusable matching rule;
- audit event sufficient to undo;
- invalidation of stale derived home/detail projections;
- no filename mutation.

#### Undo

At minimum, expose `Undo last match correction` immediately after commit and retain an audit record. A full arbitrary-history editor can be deferred.

### 17.16 Scan status and diagnostics panel

Accessible from the shell status indicator and Settings.

Displays:

- current/last scan state;
- root name;
- current phase;
- discovered/processed counts;
- started/completed timestamps;
- error/warning counts;
- whether missing-file reconciliation was committed;
- number of downstream jobs queued;
- root availability/permission state;
- button to rescan;
- button to retry failures;
- button to export diagnostics.

Never show a meaningless spinner indefinitely. Every running operation must expose a phase and heartbeat timestamp. Detect a stale job and offer recovery.

### 17.17 Library settings

Per library root:

- friendly name;
- provider display name/URI summary;
- access status;
- last successful scan;
- file counts;
- auto-scan setting;
- include/exclude glob-like rules where supported;
- remove root from catalog;
- repair permission;
- rescan;
- diagnostics.

Removing a root must prompt with clear semantics:

```text
Remove this library from the catalog?
Physical files will not be deleted.
Playback history and confirmed matches can be retained for reconnection or deleted separately.
```

Default: retain canonical metadata and history, mark files unavailable/removed. Offer a separate destructive cleanup action.

### 17.18 Metadata and matching settings

Settings:

- metadata provider selection, initially TMDB;
- preferred metadata language;
- region;
- include adult results, default false;
- metadata refresh interval;
- LLM verification enabled/disabled;
- provider/model configuration;
- privacy disclosure;
- auto-match policy;
- review thresholds;
- clear LLM cache;
- clear metadata cache without deleting playback history;
- developer-only prompt/schema version display.

Never present LLM confidence as an objective probability. UI labels should be `High confidence`, `Review suggested`, and `Unmatched`, derived from policy plus deterministic reason codes.

### 17.19 Player screen

The player is a dedicated route that receives a stable playback target, not an arbitrary path string.

Required controls:

- play/pause;
- seek bar;
- elapsed/remaining time;
- 10-second backward/forward controls;
- audio track selector;
- subtitle track selector;
- external subtitle selector when linked;
- playback speed, at least 0.5–2.0 where supported;
- aspect/fit mode;
- lock controls option for children/tablets;
- next episode control when a valid local next episode exists;
- back/close;
- error/retry details;
- title and episode context.

Behavior:

- controls hide after inactivity while playing;
- tapping or keyboard/remote input restores them;
- seek gestures must not accidentally conflict with system back gestures;
- pause before showing blocking playback errors;
- persist progress using the policy in section 15;
- restore orientation policy on exit;
- keep screen awake only while playing or buffering by explicit policy;
- release native player resources on disposal;
- correctly handle app lifecycle pause/background events;
- never mark complete merely because the player route closed.

#### Player launch contract

```dart
final class PlaybackRequest {
  const PlaybackRequest({
    required this.profileId,
    required this.fileId,
    this.canonicalTitleId,
    this.canonicalEpisodeId,
    this.startMode = PlaybackStartMode.resume,
  });

  final ProfileId profileId;
  final LibraryFileId fileId;
  final CanonicalTitleId? canonicalTitleId;
  final CanonicalEpisodeId? canonicalEpisodeId;
  final PlaybackStartMode startMode;
}
```

Resolve the actual media source immediately before opening it so expired permissions or disconnected roots are caught accurately.

### 17.20 Accessibility

Minimum requirements:

- semantic labels for all artwork cards and icon-only controls;
- focus order matching visual order;
- visible focus ring with adequate contrast;
- text scaling up to at least 200% without losing core actions;
- screen-reader announcements for scan completion and playback errors, not for every background progress tick;
- captions/subtitles accessible through a labeled control;
- avoid gesture-only functionality;
- minimum target sizes;
- progress bars with semantic values and denominator explanation;
- do not rely on color alone.

### 17.21 Loading, empty, and error states

Every query-backed screen must explicitly model:

```dart
sealed class ViewState<T> {
  const ViewState();
}

final class ViewLoading<T> extends ViewState<T> {}
final class ViewData<T> extends ViewState<T> {
  const ViewData(this.value, {this.isRefreshing = false});
  final T value;
  final bool isRefreshing;
}
final class ViewEmpty<T> extends ViewState<T> {
  const ViewEmpty(this.reason);
  final EmptyReason reason;
}
final class ViewFailure<T> extends ViewState<T> {
  const ViewFailure(this.failure, {this.staleValue});
  final AppFailure failure;
  final T? staleValue;
}
```

Rules:

- preserve stale/cached data during refresh failures;
- use skeletons only for initial loads;
- never replace a populated screen with a full-screen spinner for background refresh;
- empty states distinguish no library, no local matches, filters excluding all content, and unavailable root;
- failure states include retry when retry is meaningful;
- provider outage must not hide local catalog entries.

### 17.22 Localization readiness

Even if the MVP UI ships in English:

- use Flutter localization facilities from the beginning;
- no user-facing string literals scattered through widgets;
- support Unicode filenames and metadata;
- preserve Czech/Slovak diacritics;
- normalization used for search/matching must not alter display strings;
- format dates/durations through locale-aware helpers;
- design layouts for longer labels.

<a id="section-18"></a>
## 18. Navigation and route contract

Use `go_router` or an equivalent declarative router. Keep route construction centralized and typed where practical.

### 18.1 Route map

```text
/
/onboarding
/home
/movies
/movies/:titleId
/shows
/shows/:titleId
/shows/:titleId/season/:seasonNumber
/shows/:titleId/episode/:episodeId
/search
/attention
/attention/group/:groupId
/match/group/:groupId
/player/file/:fileId
/settings
/settings/libraries
/settings/libraries/:rootId
/settings/metadata
/settings/playback
/settings/privacy
/settings/diagnostics
```

Do not put raw filesystem paths, document URIs, provider tokens, or prompt data in route URLs.

### 18.2 Deep-link validation

For every ID route:

- parse into a typed ID;
- load from repository;
- handle missing/deleted entities with a recoverable not-found screen;
- verify requested file belongs to a configured root before playback;
- do not trust query parameters to override database identity.

### 18.3 Back-stack rules

- Closing player returns to the launching context when possible.
- A direct/deep-linked player falls back to details or home.
- Fix Match returns to the attention item or title details after commit.
- Switching primary destination resets or preserves nested stacks according to a documented shell policy; use stateful shell routes if needed.
- Android system back exits only from the root shell destination after normal navigation history is exhausted.

### 18.4 Navigation state restoration

Preserve:

- selected home/content row focus where reasonable;
- TV season selection;
- search query during temporary details navigation;
- scroll positions using stable page storage keys;
- no persistence of sensitive raw file paths in restoration state.

<a id="section-19"></a>
## 19. Security, credentials, privacy, and data handling

This app handles personal local filenames and may transmit selected normalized evidence to external metadata and LLM providers. Treat that as private data.

### 19.1 Threat model

Relevant threats:

- accidental disclosure of full paths or personal folder names to third parties;
- API keys embedded in source control or release artifacts;
- malicious or malformed filenames influencing prompts;
- untrusted metadata text rendered unsafely;
- path/URI traversal or confused-deputy bugs;
- stale Android grants;
- exported Android activities/services unintentionally reachable;
- diagnostics bundles containing secrets;
- arbitrary network redirects serving unexpected media or artwork;
- SQL injection through dynamic query construction;
- denial of service through huge directories, malformed media, or oversized provider responses.

### 19.2 Data classification

```text
Sensitive local:
- document URIs
- filesystem paths
- filenames/folder names
- playback history
- profile names
- local diagnostic logs

Secret:
- TMDB API token/key
- LLM provider key
- any future backend credentials

External public metadata:
- TMDB IDs/titles/descriptions/artwork references

Derived local:
- parsed hints
- fingerprints
- match scores
- thumbnail cache
```

### 19.3 Credential storage

- Never commit secrets to Git.
- Use runtime configuration for development.
- Store user-supplied keys via platform secure storage where supported.
- Redact credentials from logs, crash reports, network diagnostics, and exported bundles.
- Do not place secrets in route state, SQLite tables without documented encryption policy, or plain shared preferences.
- A production public client cannot perfectly hide a bundled third-party API key. Document provider terms and choose an acceptable architecture before distribution. For a personal/sideloaded MVP, user-supplied credentials are acceptable.
- Validate key presence and provider connectivity with a minimal endpoint before saving configuration.

### 19.4 LLM privacy minimization

Default outbound LLM payload must include only:

- sanitized relative folder/group label when needed;
- basename, not full path;
- parser outputs;
- sampled neighboring basenames;
- provider candidate records;
- canonical episode records needed for the batch;
- stable opaque local IDs.

Do not send:

- absolute paths;
- Android document URIs;
- profile names;
- playback history;
- unrelated filenames;
- subtitle contents;
- media bytes;
- API tokens inside prompt text.

Provide a settings preview that explains representative data categories sent externally.

### 19.5 Prompt-injection resistance

Treat all filenames, folder names, metadata descriptions, and provider text as untrusted data.

- Serialize them only inside structured JSON fields.
- System instructions explicitly state that text inside input fields is evidence, never an instruction.
- Do not concatenate filenames into system prompts.
- Require strict structured output.
- Validate all returned IDs against the supplied allowlist.
- Validate all returned episode IDs against the supplied canonical set.
- Reject extra fields when schema policy requires it.
- Never let the model invoke arbitrary tools, URLs, or database writes.
- Limit payload sizes and string lengths.

### 19.6 Network policy

- HTTPS only for metadata, artwork, and LLM APIs.
- Configure timeouts separately for connect, receive, and total request duration.
- Limit redirects and validate final schemes/hosts where the client allows it.
- Set maximum response sizes.
- Retry only idempotent calls and only for transient failures.
- Respect provider rate-limit headers.
- Cache successful responses according to documented policy.
- Do not fail local playback because network is unavailable.

### 19.7 Android application hardening

- Set only required components as exported.
- Do not request broad storage permissions when SAF grants suffice.
- Avoid `MANAGE_EXTERNAL_STORAGE` for the MVP.
- Request network permission only because metadata/LLM access requires it.
- Keep cleartext traffic disabled.
- Ensure debug-only providers/endpoints are not present in release manifests.
- Confirm file/content URI handling uses granted access and cannot escape the selected root.
- Avoid exposing a loopback media proxy beyond localhost if that fallback architecture is used.
- Use a random per-session bearer token for the loopback proxy and close it when playback stops.

### 19.8 Diagnostics export redaction

Default export includes:

- app/build version;
- schema version;
- device/OS summary;
- root IDs and friendly names only when user opts in;
- scan/job summaries;
- failure codes and stack traces with path redaction;
- parser/matcher reason codes;
- prompt/schema version hashes;
- dependency/runtime versions where available.

Default export excludes:

- provider keys;
- authorization headers;
- full document URIs;
- absolute paths;
- complete library listing;
- raw LLM requests/responses unless the user explicitly enables an advanced diagnostic option and sees a warning.

<a id="section-20"></a>
## 20. Logging, observability, and diagnostics

### 20.1 Structured logging contract

Use structured events rather than interpolated prose as the primary diagnostic format.

Every event should have:

```text
timestamp
level
eventName
correlationId
operationId/rootId/fileId/groupId as applicable
failureCode as applicable
properties with redaction applied
```

Example:

```json
{
  "eventName": "scan.file.parsed",
  "level": "debug",
  "correlationId": "scan_01J...",
  "rootId": "root_01J...",
  "fileId": "file_01J...",
  "parser": "sxxexx_range",
  "season": 1,
  "episodes": [1, 2, 3],
  "reasonCodes": ["EXPLICIT_SEASON_EPISODE_RANGE"]
}
```

Do not log full paths by default. A development-only verbose mode may log sanitized relative paths.

### 20.2 Correlation model

- Every scan run has a `scanRunId` used as correlation ID.
- Every metadata/match batch references its source scan and group ID.
- Every LLM attempt references match attempt ID, prompt version, schema version, and cache key.
- Every playback session has a session ID linked to file/profile/title/episode IDs.
- UI errors show a short diagnostic ID derived from the relevant operation ID.

### 20.3 Log levels

```text
trace: very detailed loops; disabled by default
 debug: parser/probe/matcher decisions without sensitive fields
 info: lifecycle milestones and successful operations
 warn: recoverable anomalies, ambiguous mappings, transient provider failures
error: operation failed but app remains usable
fatal: database/bootstrap failure preventing normal use
```

Do not classify expected `unmatched` outcomes as errors.

### 20.4 Required event families

```text
app.bootstrap.*
database.migration.*
library.permission.*
scan.*
reconciliation.*
parser.*
probe.*
metadata.*
matcher.deterministic.*
matcher.llm.*
artwork.*
thumbnail.*
playback.*
progress.*
job.*
ui.failure.*
diagnostics.export.*
```

### 20.5 In-app diagnostics

Developer/advanced diagnostics screen must show:

- app version/build mode;
- database schema version;
- queued/running/failed jobs;
- last scan summaries;
- root grant/access state;
- metadata provider status;
- LLM status without revealing key;
- cache sizes;
- player backend/runtime details;
- recent warnings/errors;
- actions to copy diagnostic summary, export bundle, retry failed jobs, and clear nonessential caches.

### 20.6 Crash handling

- Catch Flutter framework errors and zone-level uncaught errors.
- Persist a redacted local crash record before optional external reporting.
- Do not install a third-party crash reporter without an explicit privacy decision.
- On next startup, surface a non-blocking notice and diagnostics ID.
- Never loop on a crashing background job; use attempt limits/dead-letter state.

<a id="section-21"></a>
## 21. Testing strategy

The project is not complete when it works on a hand-picked happy path. The tests must codify the real library fixture and all major failure modes.

### 21.1 Test pyramid

```text
many pure unit tests
many repository/database tests
focused adapter contract tests
widget and golden tests for stable screens
end-to-end integration tests for critical flows
small number of real-device smoke tests
```

All normal CI tests must be deterministic, offline, and free of paid API calls.

### 21.2 Test directories

```text
test/
  fixtures/
    media_library/
      files.txt
      expected_inventory.json
      parser_expectations.json
    metadata/
      tmdb_search_bluey.json
      tmdb_search_peppa.json
      tmdb_show_episodes_*.json
    llm/
      title_match_requests/
      title_match_responses/
      episode_match_requests/
      episode_match_responses/
    probe/
      ffprobe_*.json
  unit/
  database/
  scanner/
  parser/
  grouping/
  metadata/
  matching/
  playback/
  presentation/
  integration/

golden/
  home/
  movie_details/
  show_details/
  attention/
  player/
```

Copy the supplied development listing into `test/fixtures/media_library/files.txt` as a regression fixture. Do not modify it to make parsing easier. Expected output belongs in separate files.

### 21.3 Fixture inventory acceptance test

The fixture ingestion test must assert at least:

```text
1168 non-empty input lines
816 .mkv paths before AppleDouble exclusion
287 .mp4 paths before AppleDouble exclusion
55 .srt paths before AppleDouble exclusion
16 AppleDouble entries total
1088 real video entries after ignored-file policy
54 real .srt sidecars after ignored-file policy
```

It must also assert ignored categories:

- `.stfolder`/Syncthing marker;
- `.gitkeep`;
- `.sfv`;
- `.txt` release artifacts;
- `.jpg` release images unless accepted as local artwork by naming policy;
- `._*` AppleDouble files.

Do not make the acceptance test depend on host filesystem ordering.

### 21.4 Parser fixture acceptance test

At minimum, the parser fixture baseline must classify the 1,088 real videos into the previously measured broad pattern buckets:

```text
754 standard SxxExx-style entries
156 NxNN / 1x07-style entries
101 natural-language Season N Episode N entries
56 explicit episode-range entries
12 chained multi-episode entries
5 movie/year entries identifiable by the narrow fixture heuristic
2 letter-suffix episode entries
1 explicit special entry
1 intentionally unclassified title-only episode file
```

These categories may overlap at an implementation-detail level, so the canonical expectation file must define precedence and one primary parser classification per path. If improved parsing intentionally changes the bucket counts, update the expectation file in the same change and explain why. Never silently weaken assertions.

Required exact parser examples:

```text
SpongeBob SquarePants S05E01 Friend or Foe.mkv
  title = SpongeBob SquarePants
  season = 5
  episodes = [1]

Octonauts.Above.And.Beyond.S02E07E08....mkv
  season = 2
  episodes = [7, 8]

SpongeBob ... S01E01-E03 ...mkv
  season = 1
  episodes = [1, 2, 3]

Spongebob Squarepants S06E11b ...mkv
  season = 6
  episode = 11
  suffix = b
  warning = NON_STANDARD_EPISODE_SUFFIX

Prasiatko Peppa/.../1x07 Maminka pracuje.mkv
  season = 1
  episodes = [7]
  localized title evidence retained

Ben and Holly’s Little Kingdom ｜ Season 1 ｜ Episode 10｜ Kids Videos.mp4
  season = 1
  episodes = [10]

Ben and Holly's Little Kingdom ｜ Hard Times ｜ Full Episode Season 2.mp4
  season = 2
  episode = null
  parsed episode title includes Hard Times
  status requires metadata/title-based resolution
```

### 21.5 Normalization tests

Test separately:

- case folding;
- Unicode normalization;
- punctuation removal;
- separator normalization (`.`, `_`, spaces, pipes);
- apostrophe variants;
- diacritic-insensitive comparison while preserving display text;
- release-token removal;
- year extraction without interpreting episode numbers as years;
- title aliases;
- Czech/Slovak localized names;
- names containing digits that are not years/episodes;
- bracketed release groups;
- malformed/unbalanced brackets;
- very long filenames;
- control characters and invalid Unicode replacement behavior.

### 21.6 Scanner unit and contract tests

Use a fake storage adapter capable of simulating:

- recursive trees;
- duplicate provider IDs;
- reordered enumeration;
- permission denied mid-scan;
- root disconnected before scan;
- disappearing file during stat/probe;
- file growing between observations;
- duplicate events;
- slow reads;
- cancellation;
- malformed metadata;
- cyclic provider behavior even if the underlying API should prevent it;
- 10,000+ entries without loading all content bytes.

Assertions:

- a complete scan marks unseen existing rows missing only after enumeration/reconciliation succeeds;
- a failed/cancelled scan never mass-deletes or mass-marks unseen rows missing;
- unchanged files do not enqueue parse/probe work again;
- moved files with matching strong fingerprints can retain identity under policy;
- temporary root loss marks root unavailable, not every file permanently deleted;
- `._` artifacts never become playable media rows;
- sidecars link deterministically where basenames match.

### 21.7 Database tests

Use an actual SQLite database, not mocks, for repository and migration tests.

Required tests:

- fresh database creation;
- every migration from each supported historical schema snapshot;
- foreign keys enabled;
- unique constraints and conflict behavior;
- cascade/restrict semantics;
- transaction rollback on injected failure;
- reactive query updates;
- concurrent job claiming;
- stale job recovery;
- profile-isolated playback progress;
- many-to-many file/episode mappings;
- one episode with multiple files;
- one file with multiple episodes;
- root removal retention policy;
- manual match precedence over automated refresh;
- metadata refresh does not overwrite manual fields;
- derived watch-state recomputation;
- indexes used for critical queries, inspected with `EXPLAIN QUERY PLAN` where useful.

Drift schema snapshots and migration test helpers must be checked into source control according to the chosen Drift tooling workflow.

### 21.8 Metadata adapter tests

Use recorded/sanitized JSON fixtures from official provider responses.

Test:

- TV and movie search;
- pagination;
- localized/alternative titles;
- year extraction;
- empty results;
- ambiguous remakes;
- season 0/specials;
- missing fields/null images;
- future/unaired seasons;
- rate limiting;
- 401/403 credential failures;
- 404 stale IDs;
- 429 retry timing;
- 500/transient failures;
- malformed or oversized responses;
- offline cache fallback;
- ETag/conditional requests if implemented;
- attribution fields retained where required.

No test may depend on the live TMDB service unless explicitly tagged as a developer-only integration test and excluded from normal CI.

### 21.9 Deterministic matcher tests

Build table-driven tests for reason-code combinations and score policy.

Cases:

- exact title + exact year movie;
- same title, different remake years;
- exact alias/localized title;
- strong folder context and weak filename;
- season exists but episode does not;
- explicit season/episode with conflicting episode title;
- translated episode title with exact numbers;
- multi-episode range;
- duplicate local release;
- movie stored under `TV Shows`;
- show-like filename stored under `Movies`;
- candidate type conflict;
- candidate with no relevant season;
- manual rule override;
- ignored group;
- stale rule whose provider entity no longer exists;
- deterministic threshold boundaries.

Confidence score tests must not merely assert a floating-point value. Assert the decision, contributing reason codes, contradictions, and score range/tier.

### 21.10 LLM contract tests

Use a fake LLM provider and captured fixtures. Required tests:

- request contains only allowed candidate IDs;
- full paths and URIs are absent;
- filenames containing instruction-like text remain data;
- valid strict-schema result accepted;
- invented provider ID rejected;
- invented episode ID rejected;
- wrong media type rejected;
- extra output fields rejected according to schema mode;
- invalid JSON rejected/retried once under policy;
- refusal/unmatched handled without error severity inflation;
- timeout and 429 behavior;
- cache hit avoids provider call;
- prompt/schema/model version changes invalidate cache;
- identical normalized request produces stable cache key;
- manual match prevents later LLM overwrite;
- batch size/character limits enforced;
- all output reasons are from an allowlisted enum when configured.

Do not test whether the LLM is universally “smart.” Test the boundaries around it and maintain an optional evaluation suite for semantic quality.

### 21.11 LLM evaluation dataset

Maintain a versioned, human-reviewed evaluation set derived from representative filenames, including:

- English standard names;
- Czech and Slovak names;
- aliases such as Peppa Pig / Prasiatko Peppa;
- exact year disambiguation;
- title-only episodes;
- multiple candidate remakes;
- multi-episode ranges;
- misleading release-group names;
- movies in TV folders;
- conflicting episode numbering orders.

Evaluation output:

```text
title selection accuracy
episode mapping precision
episode mapping recall
unmatched precision
unsafe invented-ID count (must be zero after validator)
manual-review rate
mean/percentile token use when available
```

Run this suite manually or in a protected CI job with explicit credentials and cost limits. Never gate ordinary pull requests on a nondeterministic paid call.

### 21.12 Probe tests

Use small legal/generated media fixtures where possible, not copyrighted media.

Test:

- MP4 and MKV detection;
- H.264/H.265 metadata extraction;
- multiple audio tracks;
- embedded subtitles;
- external SRT linkage;
- corrupt/truncated file;
- unsupported codec reporting;
- zero duration;
- variable frame rate metadata;
- cancellation;
- timeout;
- a combined episode file;
- provider URI/stream input where supported;
- probe result cache invalidation when identity changes.

### 21.13 Playback tests

Abstract the playback engine sufficiently to test application behavior with a fake player.

Test:

- resume position selection;
- play from beginning;
- periodic progress persistence throttling;
- persistence on pause, seek complete, lifecycle pause, route close, and completion;
- no write on every position event;
- completion threshold boundaries;
- replay clears/revises completion according to policy;
- shared combined-file progress behavior;
- next locally available episode selection;
- no next action when unavailable;
- alternate version selection;
- root revoked between details and play;
- player initialization failure;
- subtitle/audio track selection persistence if implemented;
- profile isolation;
- wake-lock/orientation cleanup.

Real-device smoke matrix should include at least representative H.264 MP4, H.265 MKV, external SRT, multi-audio, and an intentionally unsupported/corrupt file.

### 21.14 Widget tests

Required screens/states:

- first-run onboarding;
- no-library state;
- cached home with background refresh;
- home sections conditionally hidden;
- movie details with one/multiple/unavailable versions;
- TV details with available/missing/in-progress/watched episodes;
- combined-file badge;
- Needs Attention list;
- Fix Match candidate selection and scope preview;
- scan progress and cancellation;
- permission repair;
- offline metadata warning with local catalog intact;
- player controls and error state;
- large text scale;
- keyboard/focus traversal.

Use semantic finders and stable keys for critical controls. Avoid tests coupled to internal widget nesting.

### 21.15 Golden tests

Golden tests should cover representative medium/expanded landscape layouts and a compact portrait sanity set.

Control:

- fonts through deterministic test configuration;
- locale;
- device pixel ratio;
- dates/times;
- generated artwork seeds;
- network images replaced by fixture providers;
- animations disabled or settled.

Goldens detect visual regressions but do not replace semantic/widget assertions.

### 21.16 End-to-end integration tests

Critical flow A:

```text
fresh install
→ choose fake/test library root
→ scan
→ catalog appears
→ open Bluey
→ play episode
→ advance fake position
→ leave player
→ restart app
→ resume state retained
```

Critical flow B:

```text
scan ambiguous/localized group
→ Needs Attention
→ choose correct TMDB candidate
→ confirm group scope
→ episode mappings committed
→ title appears in catalog
→ correction survives rescan
```

Critical flow C:

```text
successful scan
→ simulate permission/root loss
→ cached catalog remains
→ playback reports unavailable
→ repair grant
→ rescan
→ file identity/history retained
```

Critical flow D:

```text
one file maps to episodes 1–3
→ each canonical episode shows Combined file
→ launch succeeds
→ no duplicate physical file rows
```

### 21.17 Performance tests and budgets

Initial budgets on a representative mid-range Android tablet, measured and documented rather than treated as universal guarantees:

```text
cold app shell with cached DB: target < 2.5 s
warm app shell: target < 1.0 s
home query/render first meaningful content: target < 500 ms after DB open
fixture path enumeration/index reconciliation: target < 10 s excluding probe/network
UI jank: no sustained work on main isolate; target 60 fps where device supports it
search response after debounce: target < 150 ms for 10k catalog entities
progress DB writes: no more than policy interval plus lifecycle events
memory: no loading all poster/full-resolution image bytes at once
```

Measure:

- 1,000-file fixture;
- synthetic 10,000-file tree;
- synthetic 100,000-path parser/grouping benchmark outside UI where feasible;
- cold and warm database queries;
- migration duration;
- thumbnail cache pressure.

Do not optimize based solely on guesses. Check in benchmark harnesses and record baselines.

### 21.18 Reliability/fault-injection tests

Inject failures at every external boundary:

- storage grant revoked;
- file removed;
- database full/read-only;
- disk cache full;
- process killed between job claim and completion;
- network offline;
- provider timeout/rate limit;
- LLM malformed response;
- probe crash/timeout;
- artwork decode failure;
- app lifecycle interruption during playback/scan;
- clock changes;
- duplicate job delivery.

Core invariant: no single adapter failure corrupts canonical mappings, manual corrections, or playback history.

<a id="section-22"></a>
## 22. CI, code quality, and release engineering

### 22.1 Required local/CI checks

At minimum:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Add package-specific tests if using a workspace:

```bash
dart test packages/media_domain
dart test packages/media_parser
dart test packages/media_matcher
```

Run code generation consistency checks:

```bash
dart run build_runner build --delete-conflicting-outputs
git diff --exit-code
```

The exact commands may evolve with the selected workspace tool, but CI must fail on stale generated code.

### 22.2 CI pipeline stages

```text
1. checkout and toolchain setup
2. dependency resolution with lockfile
3. formatting
4. static analysis
5. code generation verification
6. pure Dart/unit tests
7. database/migration tests
8. Flutter widget/golden tests
9. Android debug build
10. optional signed release build on protected branch
11. artifact/report upload
```

Parallelize independent test suites after correctness is established.

### 22.3 Toolchain pinning

Pin and commit:

- Flutter SDK strategy/version via FVM or documented equivalent;
- Dart version inherited from Flutter;
- `pubspec.lock` for the application;
- Android Gradle/JDK/Kotlin/NDK versions required by dependencies;
- schema/prompt versions;
- native player/probe dependency versions.

Do not blindly run major dependency upgrades during feature work. Use dedicated upgrade changes with changelog review and smoke tests.

### 22.4 Branch and commit discipline for the coding agent

The autonomous coding assistant must:

- make cohesive, reviewable commits when Git operations are authorized;
- not rewrite unrelated user changes;
- inspect `git status` before and after edits;
- include generated files only when required;
- keep formatting-only churn separate when substantial;
- never commit credentials, local paths, or personal fixture copies outside approved test fixtures;
- include migration and tests in the same change as schema evolution;
- include prompt/schema tests in the same change as LLM contract changes.

Suggested commit prefixes:

```text
feat:
fix:
refactor:
test:
docs:
build:
chore:
```

### 22.5 Build variants

Define at least:

```text
debug
release
```

Optionally define flavors later:

```text
dev: verbose diagnostics, fixture/demo adapters, nonproduction app ID
prod: production app ID, strict logging/redaction
```

Ensure fixture/demo adapters cannot be activated accidentally in production.

### 22.6 Secrets in CI

- No external API key is required for ordinary tests.
- Protected live integration/evaluation jobs read secrets from CI secret storage.
- Never echo secret values.
- Forked pull requests must not receive protected secrets.
- Apply explicit cost and request limits to LLM evaluation jobs.
- Release signing keys remain protected and are not accessible to general test jobs.

### 22.7 Dependency and license review

Before adding a dependency, document:

- purpose;
- why standard library/current dependencies are insufficient;
- supported platforms;
- maintenance health;
- license compatibility;
- binary size/native implications;
- privacy/network implications;
- fallback/removal strategy.

Run periodic dependency audit and outdated checks. Do not add packages merely to avoid writing a small stable helper.

### 22.8 Release checklist automation

Automate what can be automated:

- version/build number validation;
- changelog presence;
- migration tests;
- release analyze/tests;
- Android release build;
- manifest permission diff;
- secret scanning;
- dependency/license report;
- artifact checksum;
- smoke-test checklist generated with the build.

<a id="section-23"></a>
## 23. Developer workflow and commands

### 23.1 Initial repository creation

Recommended sequence, adjusted to the current stable Flutter toolchain at implementation time:

```bash
mkdir local_media_hub
cd local_media_hub
flutter create --platforms=android,macos,windows,linux app
mkdir -p packages/media_domain
mkdir -p packages/media_parser
mkdir -p packages/media_matcher
mkdir -p packages/media_metadata
mkdir -p packages/media_storage
mkdir -p packages/media_playback
```

Do not create every package merely for appearance. Start with the modular boundaries in section 3, and combine packages only when the dependency graph remains enforceable.

### 23.2 Standard development loop

```text
1. Read this specification and relevant ADR.
2. Inspect current implementation and tests.
3. State the smallest vertical slice.
4. Write/adjust failing tests.
5. Implement the slice.
6. Run targeted tests.
7. Run format/analyze/full relevant suite.
8. Review diff for architecture/privacy regressions.
9. Update docs/ADR/status matrix.
```

### 23.3 Code generation

Centralize generated-code commands in scripts or a task runner:

```bash
./tool/generate.sh
./tool/check.sh
./tool/test_fixture.sh
```

Scripts must work from repository root, fail fast, and return nonzero status on errors. Avoid OS-specific shell assumptions where practical; provide PowerShell equivalents only when needed for Windows development.

### 23.4 IDE run configurations

Create documented Rider run configurations for:

- Android tablet/emulator app;
- Flutter desktop app where enabled;
- all tests;
- parser fixture tests;
- database migration tests;
- build runner watch;
- optional LLM evaluation suite with explicit environment flag;
- benchmark harness.

Do not store secrets directly in shared `.run` files. Reference environment variables or untracked local configuration.

### 23.5 Debug data and fixtures

Implement a development-only command/action to:

- import the path-list fixture into a fake storage repository;
- seed recorded metadata fixtures;
- seed deterministic match outcomes;
- reset the development database;
- simulate root disconnection/permission loss;
- simulate provider outage;
- inspect queued jobs.

This enables UI and workflow development without requiring the actual media files.

### 23.6 Documentation that must stay current

```text
README.md
AGENTS.md or this build specification
ARCHITECTURE.md or ADR directory
PRIVACY.md
provider setup guide
fixture/update guide
database migration guide
release checklist
```

The coding assistant must update documentation when implementation changes invalidate it.

<a id="section-24"></a>
## 24. Architecture decision records

Create `docs/adr/` and record significant decisions. Use this template:

```markdown
# ADR-NNN: Title

- Status: proposed | accepted | superseded | rejected
- Date: YYYY-MM-DD
- Decision owners: ...

## Context

## Decision

## Alternatives considered

## Consequences

## Validation / reversal criteria

## References
```

Required initial ADRs:

```text
ADR-001 Modular Flutter architecture and dependency direction
ADR-002 Drift/SQLite persistence
ADR-003 Android SAF storage access
ADR-004 Android media source strategy for media_kit
ADR-005 Metadata provider abstraction with TMDB first
ADR-006 Deterministic matcher plus bounded LLM verifier
ADR-007 Many-to-many canonical episode/file mapping
ADR-008 Background job persistence model
ADR-009 Playback progress and completion semantics
ADR-010 Credential and privacy model
ADR-011 Media probing implementation
ADR-012 Canonical episode ordering policy
```

ADR-004 is a release blocker for Android because the exact content-URI/descriptor/proxy approach must be proven on a real target device.

<a id="section-25"></a>
## 25. Delivery plan and milestone acceptance criteria

Implement vertical capabilities. A milestone is complete only when its acceptance criteria and tests pass.

### Milestone 0: technical risk spikes

#### Goal

Prove the platform assumptions before building the catalog.

#### Work

- Create minimal Flutter Android app in Rider-compatible project.
- Select a directory through SAF and persist the grant.
- Enumerate nested documents without broad storage permission.
- Open representative MP4 and MKV files from the selected provider through the chosen media source bridge.
- Test external SRT loading.
- Test app restart with persisted grant.
- Test grant revocation behavior.
- Prove one probing strategy against SAF-backed media.
- Record results in ADR-003, ADR-004, and ADR-011.

#### Acceptance

- Real Android tablet can choose the media folder.
- App restarts and reopens the same root without asking again while the grant remains valid.
- At least representative H.264 MP4 and H.265/MKV files play, or unsupported behavior is precisely documented.
- External SRT is demonstrated or explicitly scheduled with a validated fallback.
- Permission loss produces a controlled state.
- No `MANAGE_EXTERNAL_STORAGE` permission.
- Spike code is either hardened into adapters or deliberately removed.

### Milestone 1: repository scaffold and persistence

#### Work

- Establish workspace/modules and dependency rules.
- Add linting, CI skeleton, app shell.
- Implement Drift schema version 1 and repositories for profiles, roots, scan runs, files, jobs, and settings.
- Add migration test harness and schema snapshots.
- Implement typed IDs and failure model.
- Add structured logging foundation.

#### Acceptance

- Fresh DB initializes.
- Restart persists root/profile/settings.
- Repository tests use real SQLite.
- Static analysis and CI pass.
- Presentation cannot import infrastructure implementation classes directly.

### Milestone 2: scanner and reconciliation

#### Work

- Implement storage gateway and SAF adapter.
- Implement ignored-file policy.
- Implement scan state machine, stable observation, identity strategy, reconciliation, and job scheduling.
- Link obvious sidecars by normalized basename.
- Add scan diagnostics UI and cancellation.
- Import the supplied path-list fixture through a fake adapter.

#### Acceptance

- Fixture yields expected 1,088 real videos and 54 real SRT sidecars after exclusions.
- Repeated unchanged scan enqueues no unnecessary derived work.
- Cancelled/failed scan never marks all unseen files missing.
- Root loss preserves catalog/history and marks availability correctly.
- 10,000-entry synthetic scan does not freeze UI.

### Milestone 3: parser and local grouping

#### Work

- Implement parser pipeline and normalization.
- Implement primary parser classifications and reason codes.
- Implement grouping by root/folder/title hints.
- Support ranges, chained episodes, `NxNN`, natural-language season/episode, specials, suffixes, localized evidence, and movie/year patterns.
- Build parser fixture expectation file and reporting CLI/tool.

#### Acceptance

- Exact fixture baseline tests pass.
- One intentionally unclassified fixture file remains safely unresolved rather than guessed.
- Parser never treats release codec/resolution tokens as title identity.
- Groups retain representative/anomaly files and coverage summaries.
- Parsing is pure, deterministic, and benchmarked.

### Milestone 4: metadata provider and canonical catalog

#### Work

- Implement provider-neutral metadata port.
- Implement TMDB adapter with credentials, caching, retries, localization, search, title details, seasons, episodes, aliases, artwork references, and external IDs.
- Add canonical database repositories.
- Add metadata settings and offline behavior.

#### Acceptance

- Recorded fixtures identify representative movies/shows.
- Full canonical season/episode structures persist.
- Provider outage leaves local catalog usable.
- Alternative/localized titles are retained.
- No live provider dependency in normal tests.
- Attribution/terms requirements are documented and represented in UI where required.

### Milestone 5: deterministic matching and manual review

#### Work

- Implement candidate generation/scoring.
- Implement policy decision tiers and reason codes.
- Implement file-title and file-episode links.
- Implement many-to-many mappings and duplicate versions.
- Build Needs Attention and Fix Match workflows.
- Persist manual rules and precedence.

#### Acceptance

- Movies under a TV folder can still classify as movies.
- Peppa/Prasiatko localized groups can resolve to one canonical show when candidates support it.
- Multi-episode files map to multiple canonical episodes.
- Multiple files can map to one canonical episode.
- Manual corrections survive rescans and metadata refresh.
- Low-confidence cases remain reviewable and playable.

### Milestone 6: bounded LLM verifier

#### Work

- Implement provider-neutral LLM verification port.
- Add strict schemas and prompts from section 13.
- Add request sanitization, candidate allowlists, validator, caching, versioning, rate/cost controls, retry policy, and settings/privacy disclosure.
- Implement title and episode verification only after provider candidate retrieval.
- Build optional evaluation harness.

#### Acceptance

- Model can select only supplied IDs.
- Invented IDs are rejected.
- Full paths/URIs never leave the app under default policy.
- LLM disabled mode remains fully functional with deterministic/manual matching.
- Fixture-derived evaluation set exists.
- No paid calls in normal CI.
- Manual match is never overwritten by model output.

### Milestone 7: catalog UI

#### Work

- Implement responsive shell, onboarding, home, movies, shows, search, movie details, TV details, season/episode states, settings, and diagnostics.
- Add artwork caching/fallbacks.
- Add accessibility and localization scaffolding.
- Add widget/golden tests.

#### Acceptance

- Filesystem is absent from normal catalog UX.
- Cached catalog renders before background network work.
- Missing local episodes are clearly distinct from unavailable roots.
- Combined files and alternate versions are represented honestly.
- Medium/expanded landscape layouts pass goldens and manual tablet review.
- Keyboard/focus traversal works.

### Milestone 8: playback and progress

#### Work

- Integrate media_kit through playback gateway.
- Implement player route/controls, track selection, sidecars, lifecycle handling, resume, completion, next episode, version selection, and persistence throttling.
- Add fake-player tests and real-device codec smoke matrix.

#### Acceptance

- Representative library formats play according to documented capability matrix.
- Progress survives restart.
- Profile state is isolated.
- Completion threshold behaves at boundaries.
- Combined files do not fabricate episode seek offsets.
- Permission/root loss is recoverable.
- Player resources, wake lock, and orientation state clean up correctly.

### Milestone 9: hardening and personal release

#### Work

- Fault injection and performance work.
- Diagnostics export/redaction.
- Dependency/license review.
- Release build pipeline.
- Privacy documentation.
- Migration and backup/restore checks.
- Full real-library validation on target tablet.

#### Acceptance

- No P0/P1 known defects.
- All release checks pass.
- App handles offline mode, root loss, provider failure, malformed model output, corrupt media, and process restart without data corruption.
- Full target library scans and catalog renders within measured acceptable budgets.
- Signed installable artifact is produced through documented process.

<a id="section-26"></a>
## 26. Definition of Done

A feature is done only when all applicable items are true:

- behavior meets this specification or an accepted ADR/deviation updates it;
- domain/application boundaries are preserved;
- failure and cancellation paths are implemented;
- user-facing loading/empty/error states exist;
- unit/repository/widget/integration tests are added at the correct layer;
- fixture regressions are considered;
- accessibility semantics are present;
- strings are localized through the app localization layer;
- structured logs and redaction are correct;
- no secrets or personal paths are committed;
- database changes include migrations and migration tests;
- background work is idempotent;
- manual mappings/history cannot be silently overwritten;
- format/analyze/tests pass;
- documentation and ADRs are updated;
- code has no placeholder production implementations, swallowed exceptions, or unexplained TODOs;
- performance impact is measured for hot paths;
- release-platform behavior is tested when native integration is involved.

<a id="section-27"></a>
## 27. Release-blocking quality gates

The first personal-use release must not ship with any of these conditions:

- filesystem access depends on a temporary picker result that fails after restart;
- app needs broad all-files Android permission without an accepted revised requirement;
- scan cancellation can mark the entire library missing;
- model output can create arbitrary provider IDs;
- one-file/one-episode schema assumption remains;
- raw full paths are transmitted to LLM by default;
- progress is written on every player tick;
- database has untested migrations;
- user cannot repair an incorrect match;
- unavailable root is represented as permanent deletion;
- metadata outage prevents local playback;
- player failures expose raw stack traces only;
- API credentials are committed or logged;
- real fixture regression tests are absent;
- release build has unreviewed exported Android components;
- unsupported formats fail silently.

<a id="section-28"></a>
## 28. Backlog beyond MVP

These are explicitly deferred unless pulled forward through an ADR:

- multiple visible user profiles and PINs;
- profile synchronization across devices;
- server/NAS catalog architecture;
- SMB/NFS discovery and authentication;
- Chromecast/AirPlay/DLNA casting;
- Android TV and dedicated remote UI;
- iOS distribution and Files-provider storage;
- web client;
- transcoding/server-side streaming;
- subtitle downloading and provider integration;
- intro/credits detection;
- per-episode offsets inside combined files;
- chapter support;
- trailer playback;
- collections/franchises;
- parental ratings/controls;
- automatic file renaming/organization;
- physical deletion or file management;
- watch-history import/export from other products;
- cloud backup;
- recommendations beyond deterministic resume/next/recently added;
- multi-provider metadata reconciliation;
- TVDB episode-order integration;
- custom metadata/NFO editing;
- hardware capability scoring and automatic transcode alternatives.

<a id="section-29"></a>
## 29. Implementation status matrix

The coding assistant must maintain this table in the repository and update it truthfully. Do not mark an item complete solely because interfaces or placeholders exist.

| Capability | Status | Tests | Platform validation | Notes/ADR |
|---|---|---|---|---|
| App scaffold | Not started | — | — | — |
| Drift schema/migrations | Not started | — | — | ADR-002 |
| Android SAF root grant | Not started | — | — | ADR-003 |
| SAF recursive enumeration | Not started | — | — | ADR-003 |
| Media source bridge | Not started | — | — | ADR-004 |
| Scanner/reconciliation | Not started | — | — | — |
| Parser fixture baseline | Not started | — | — | — |
| Local grouping | Not started | — | — | — |
| TMDB adapter | Not started | — | — | ADR-005 |
| Deterministic matcher | Not started | — | — | ADR-006 |
| Manual Fix Match | Not started | — | — | — |
| LLM verifier | Not started | — | — | ADR-006/010 |
| Canonical catalog UI | Not started | — | — | — |
| Player/progress | Not started | — | — | ADR-009 |
| Diagnostics/export | Not started | — | — | — |
| Release pipeline | Not started | — | — | — |

Allowed statuses:

```text
Not started
Spike
In progress
Blocked
Implemented, unvalidated
Complete
```

<a id="section-30"></a>
## 30. Coding-agent execution protocol

This section is written directly for the AI coding assistant that will implement the product.

### 30.1 Before writing code

1. Read this entire file.
2. Inspect the repository tree and existing status matrix.
3. Read all accepted ADRs relevant to the current milestone.
4. Inspect `git status`; preserve user work.
5. Confirm the current Flutter/Dart/Android toolchain from project files and official current documentation.
6. Identify the next incomplete vertical slice from section 25.
7. State assumptions in the work log; do not silently invent product behavior.
8. Locate existing tests and fixtures before adding abstractions.
9. For native/platform work, prioritize a runnable spike and real-device validation over speculative wrappers.

### 30.2 While implementing

- Keep domain code free of Flutter/platform imports.
- Use typed IDs instead of passing raw strings everywhere.
- Use explicit immutable request/result objects.
- Preserve cancellation through async boundaries.
- Make background operations restart-safe and idempotent.
- Keep DB transactions bounded.
- Do not perform file enumeration, hashing, probing, JSON-heavy work, or image decoding on the UI isolate when it can cause jank.
- Do not expose infrastructure response DTOs directly to UI.
- Do not let provider/network failures erase cached state.
- Do not let automated results supersede manual matches.
- Do not implement one-to-one shortcuts where the schema requires many-to-many.
- Do not transmit unredacted paths to external services.
- Do not invent API behavior. Verify current official docs at implementation time.
- Add tests with each behavior, not at the end of the entire milestone.
- Run the narrowest relevant test repeatedly, then the full affected suite.

### 30.3 When blocked or uncertain

Do not paper over uncertainty with placeholder success behavior.

For a material architecture uncertainty:

1. create/update an ADR as `proposed`;
2. build the smallest empirical spike;
3. record observed behavior and environment;
4. choose the least irreversible option;
5. keep the user-visible system honest about unsupported behavior;
6. mark the status matrix `Blocked` or `Spike` until validated.

Examples requiring empirical validation:

- media_kit handling of Android SAF content URIs;
- file-descriptor lifetime through native bridge;
- subtitle loading from document providers;
- probe support for non-path sources;
- background execution limits on target Android versions;
- codec/HDR behavior on the target tablets.

### 30.4 After each vertical slice

1. Run formatter.
2. Run analyzer.
3. Run targeted tests.
4. Run all tests for affected packages.
5. Run migration tests if persistence changed.
6. Run fixture tests if scanner/parser/grouping/matching changed.
7. Review logs for accidental sensitive data.
8. Inspect the final diff.
9. Update status matrix and relevant docs.
10. Record commands and results in the work summary.
11. State any unvalidated platform assumptions explicitly.

### 30.5 Forbidden implementation behaviors

- No fake production implementations presented as complete.
- No empty `catch` blocks.
- No `catch (e) { return null; }` that erases failure semantics.
- No broad `dynamic` maps across domain boundaries when typed models are feasible.
- No global mutable singleton service locator.
- No direct database access from widgets.
- No HTTP calls from widgets.
- No platform channel calls from widgets.
- No raw SQL built from untrusted text.
- No direct model response committed without schema and allowlist validation.
- No hardcoded personal filesystem paths.
- No hardcoded provider credentials.
- No hardcoded fixture counts in production code.
- No physical file deletion in MVP.
- No automatic file renaming.
- No silent fallback that changes a movie into a show or vice versa.
- No mass missing/deletion reconciliation after an incomplete scan.
- No assumptions that top-level `Movies`/`TV Shows` folders are authoritative.
- No assumptions that one file equals one episode.
- No assumptions that one episode has one file.
- No assumptions that filename language equals metadata display language.
- No assumptions that extension guarantees codec support.

### 30.6 Required final response from the coding agent for each task

The agent’s completion message must include:

```text
Implemented
- concise behavior-level summary

Key decisions
- architecture/policy decisions and ADR references

Validation
- exact commands run and pass/fail results
- real-device/manual checks, if any

Known limitations
- only actual remaining limitations or unvalidated assumptions

Files changed
- concise grouped list
```

Do not claim completion if required tests or platform validation did not run. State the concrete blocker.

<a id="section-31"></a>
## 31. First implementation task for the coding agent

Start with Milestone 0, not the polished catalog UI.

Use this task statement:

```text
Read LOCAL_MEDIA_HUB_BUILD_SPEC.md completely.

Implement the Milestone 0 Android storage/playback/probe risk spike. Create the
smallest Flutter application that can:

1. Launch the Android Storage Access Framework directory picker.
2. Persist read access to the selected directory tree.
3. Restore and validate the grant after process restart.
4. Recursively enumerate document metadata without reading media bytes.
5. Filter obvious non-video and AppleDouble files.
6. Select one enumerated MP4 or MKV file.
7. Play it through a narrowly defined playback adapter using media_kit.
8. Load a matching external SRT when present, if technically supported by the
   selected source strategy.
9. Probe the file using the smallest viable strategy and display container,
   duration, video codec, audio codec, and stream count.
10. Display controlled states for grant revoked, file unavailable, unsupported
    source/codec, probe failure, and player initialization failure.

Do not build the final catalog, TMDB integration, LLM matching, or production
schema yet. This is an empirical platform spike.

Create or update ADR-003, ADR-004, and ADR-011 with observed results. Add unit
and adapter tests where meaningful, plus a manual test checklist for a real
Android tablet. Do not request MANAGE_EXTERNAL_STORAGE. Do not hardcode a local
path. Do not claim content-URI playback support unless it was tested on the
actual target device.

Run formatting, analysis, and tests. Report exact commands and distinguish
implemented behavior from unvalidated real-device assumptions.
```

<a id="section-32"></a>
## 32. Authoritative implementation references

Verify current versions and details at implementation time. Prefer primary documentation.

### Flutter and Dart

- Flutter desktop support: `https://docs.flutter.dev/platform-integration/desktop`
- Flutter architectural overview: `https://docs.flutter.dev/resources/architectural-overview`
- Flutter testing: `https://docs.flutter.dev/testing/overview`
- Flutter accessibility: `https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility`
- Dart packages/workspaces and language docs: `https://dart.dev/`

### Android storage

- Storage Access Framework overview: `https://developer.android.com/guide/topics/providers/document-provider`
- Shared documents/files: `https://developer.android.com/training/data-storage/shared/documents-files`
- `ACTION_OPEN_DOCUMENT_TREE`: `https://developer.android.com/reference/android/content/Intent#ACTION_OPEN_DOCUMENT_TREE`
- Persistable URI permissions: Android `ContentResolver.takePersistableUriPermission` documentation.
- `DocumentsContract`: Android API reference.

### Persistence

- Drift documentation: `https://drift.simonbinder.eu/`
- Drift migrations: `https://drift.simonbinder.eu/migrations/`
- SQLite foreign keys and transactions: `https://www.sqlite.org/`

### Playback

- media_kit repository and documentation: `https://github.com/media-kit/media-kit`
- Verify the current package documentation and platform requirements before pinning versions.

### Metadata

- TMDB API documentation: `https://developer.themoviedb.org/`
- TMDB TV search: `https://developer.themoviedb.org/reference/search-tv`
- TMDB movie search: `https://developer.themoviedb.org/reference/search-movie`
- TMDB TV season details: `https://developer.themoviedb.org/reference/tv-season-details`
- TMDB episode groups: `https://developer.themoviedb.org/reference/tv-series-episode-groups`
- TMDB attribution/terms: verify current official requirements before distribution.

### LLM structured output

- Use the selected provider’s official current structured-output/JSON-schema documentation.
- For OpenAI, verify current official API documentation at implementation time rather than relying on copied examples.
- Keep the application adapter provider-neutral.

### Media probing

- FFmpeg/ffprobe official documentation: `https://ffmpeg.org/ffprobe.html`
- Do not select the retired original FFmpegKit project without an explicit maintained-fork decision and license/maintenance review.

<a id="section-33"></a>
## 33. Final product acceptance scenario using the real fixture

The implementation is not considered functionally credible until this scenario works with the fixture-backed fake adapter and then with the actual selected library on the target tablet:

1. The app scans the root without cataloging `._` files, `.sfv`, `.gitkeep`, release `.txt`, or Syncthing markers as playable titles.
2. It creates canonical movie entries for examples such as Zootopia and Astro Kid even when folder placement is misleading.
3. It identifies SpongeBob across multiple season-release folder styles.
4. It maps `S01E01-E03` to three canonical episodes backed by one file.
5. It maps `S02E07E08` to two canonical episodes backed by one file.
6. It records `S06E11b` as a nonstandard suffix case requiring policy/review rather than silently colliding with `S06E11`.
7. It treats English Peppa Pig and localized Prasiatko Peppa/Czech files as possible versions of the same canonical show, using provider aliases and manual review where needed.
8. It handles `1x07`, `Season 1 Episode 10`, and standard `S01E01` grammars.
9. It leaves the title-only `Hard Times` file resolvable through canonical episode-title evidence rather than fabricating an episode number.
10. It links Bluey `.en.srt` sidecars to their matching MP4 files.
11. It presents canonical seasons and missing/local states independently of physical folder layout.
12. It allows the user to correct every uncertain title/episode mapping and remembers the correction.
13. It plays a selected preferred version, resumes progress after restart, and displays alternate local versions only when requested.
14. It remains usable offline after metadata has been cached.
15. It retains catalog/history when the root is temporarily unavailable and recovers after permission repair.

<a id="section-34"></a>
## 34. Closing instruction to the coding assistant

Build a dependable local media catalog and player, not a visual prototype. The catalog is canonical metadata decorated by local availability. The filesystem is an input adapter. Deterministic code owns parsing, scoring, validation, persistence, and policy. The LLM only adjudicates among bounded real candidates. Manual corrections are authoritative. Playback history is durable. Background work is restart-safe. Every uncertain behavior remains visible and repairable rather than being hidden behind a confident guess.
