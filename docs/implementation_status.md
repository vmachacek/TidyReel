# Implementation status

Status date: 2026-10-08

| Capability | Status | Tests | Platform validation | Notes/ADR |
| --- | --- | --- | --- | --- |
| App scaffold | Complete | All analyzers clean; 3 domain, 5 storage, 3 playback-contract, 20 app, 1 device-integration, and 10 Kotlin tests pass | Final debug APK built, inspected, installed, and launched on SM-T500 | Android-only Milestone 0 workspace |
| Drift schema/migrations | Not started | — | — | ADR-002 pending |
| Android SAF root grant | Complete | Kotlin permission-policy and Flutter controller tests | Picker, restart restoration, explicit release, repair state, and cold-start absence passed on SM-T500 | [ADR-003](adr/003-android-saf-storage-access.md) |
| SAF recursive enumeration | Complete | Kotlin traversal/cancellation tests; Dart classifier and scan mapping tests | Nested traversal and AppleDouble exclusion passed on SM-T500 | [ADR-003](adr/003-android-saf-storage-access.md) |
| Media source bridge | Complete | Dart adapter, failure mapping, and lifecycle tests | Direct URI MP4/MKV, seek, lifecycle, subtitle, and sequential-session checks passed on SM-T500 | [ADR-004](adr/004-android-media-source-strategy.md) |
| Media probing | Complete | Kotlin probe mapping and Dart adapter tests | Required MP4 and MKV fields returned on SM-T500 | [ADR-011](adr/011-media-probing-implementation.md) |
| Scan inventory/startup | Implemented | Inventory validation, restart, stale-operation, background refresh, and skeleton tests | [SM-T500 startup checks](manual-tests/startup-cache-android.md) | Saved library renders first; each launch refreshes in background; atomic inventory replacement; incremental reconciliation remains pending |
| Parser fixture baseline | Implemented increment | Pure Dart parser and catalog fixture tests | 268-file SpongeBob listing groups under one show, seasons 1–9 | NormieRename policies ported; full 1,088-file baseline and Unicode NFKC remain pending |
| Local grouping | Implemented | Hierarchy, ranges, chains, suffixes, unresolved episodes, localized folders, remakes | Fixture and widget tests | No physical moves or renames |
| TMDB adapter | Implemented increment | Fake HTTP, response validation, authentication, pagination, request bounds | No live token/API validation | Movie/TV search and season episodes; Android Keystore token storage |
| Deterministic matcher | Implemented increment | Exact title/year, offline cache, conflicts, stale requests, manual choices, new seasons | Fixture tests | Uncertain titles and episode orders need review |
| Manual Fix Match | Title-level implemented | Selection and preservation tests | Review sheet with alternative-title search | Episode-number correction remains pending |
| LLM verifier | Not started | — | — | ADR-006/010 pending |
| Canonical catalog UI | Implemented increment | Catalog/widget tests | Android debug build | Matched aliases merge; show → season → episode browsing |
| Player/progress | Implemented increment | Playback adapter, lifecycle and preference tests | Local playback behavior passed | Native preferences retain watchlist/resume; production database/progress semantics pending |
| Diagnostic UI | Complete | Controller, widget, and fake integration tests | Grant, scan, probe, playback, subtitle, and controlled failure states exercised | Milestone 0 only |
| Diagnostics/export | Not started | — | — | — |
| Release pipeline | Implemented; publication pending | 359 app tests, Android unit tests, signing guard checks, and Play script success/failure checks pass | Real 70.2 MB signed AAB built and signature verified with a temporary test key; no Play upload | Upload signing and verified AAB/PEM/SHA-256 export; personal APK keeps development signing; [remaining publication gates](google-play-publishing.md) |
