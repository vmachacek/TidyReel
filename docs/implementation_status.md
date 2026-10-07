# Implementation status

Status date: 2026-10-07

| Capability | Status | Tests | Platform validation | Notes/ADR |
| --- | --- | --- | --- | --- |
| App scaffold | Complete | All analyzers clean; 3 domain, 5 storage, 3 playback-contract, 20 app, 1 device-integration, and 10 Kotlin tests pass | Final debug APK built, inspected, installed, and launched on SM-T500 | Android-only Milestone 0 workspace |
| Drift schema/migrations | Not started | — | — | ADR-002 pending |
| Android SAF root grant | Complete | Kotlin permission-policy and Flutter controller tests | Picker, restart restoration, explicit release, repair state, and cold-start absence passed on SM-T500 | [ADR-003](adr/003-android-saf-storage-access.md) |
| SAF recursive enumeration | Complete | Kotlin traversal/cancellation tests; Dart classifier and scan mapping tests | Nested traversal and AppleDouble exclusion passed on SM-T500 | [ADR-003](adr/003-android-saf-storage-access.md) |
| Media source bridge | Complete | Dart adapter, failure mapping, and lifecycle tests | Direct URI MP4/MKV, seek, lifecycle, subtitle, and sequential-session checks passed on SM-T500 | [ADR-004](adr/004-android-media-source-strategy.md) |
| Media probing | Complete | Kotlin probe mapping and Dart adapter tests | Required MP4 and MKV fields returned on SM-T500 | [ADR-011](adr/011-media-probing-implementation.md) |
| Scanner/reconciliation | Not started | — | — | Milestone 0 enumerates only; no durable reconciliation |
| Parser fixture baseline | Not started | — | — | — |
| Local grouping | Not started | — | — | — |
| TMDB adapter | Not started | — | — | ADR-005 pending |
| Deterministic matcher | Not started | — | — | ADR-006 pending |
| Manual Fix Match | Not started | — | — | — |
| LLM verifier | Not started | — | — | ADR-006/010 pending |
| Canonical catalog UI | Not started | — | — | — |
| Player/progress | Spike | Playback adapter and session lifecycle tests | Local playback behavior passed; durable progress semantics were not implemented | ADR-009 pending |
| Diagnostic UI | Complete | Controller, widget, and fake integration tests | Grant, scan, probe, playback, subtitle, and controlled failure states exercised | Milestone 0 only |
| Diagnostics/export | Not started | — | — | — |
| Release pipeline | Not started | — | — | Debug build only |
