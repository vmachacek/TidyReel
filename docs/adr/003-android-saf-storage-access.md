# ADR-003: Android SAF storage access

- Status: accepted
- Date: 2026-10-07
- Decision owners: TidyReel maintainers

## Context

TidyReel needs durable, user-scoped read access to a media directory without
requesting broad storage permissions or relying on filesystem paths. Android
document providers expose stable tree and document identities whose details
must remain behind the platform boundary.

## Decision

Use `ACTION_OPEN_DOCUMENT_TREE` and request read plus persistable URI flags.
Persist only the read permission returned by the provider. At startup, list
persisted read grants and validate a root by querying its document metadata.

Treat provider authority plus document id as the opaque storage key. Rebuild a
document URI only inside the Android adapter, and reject keys whose authority
does not match the selected tree. Enumerate recursively through
`DocumentsContract` metadata queries; do not open media bytes while scanning.

Expose an explicit release action. After release, show a repair state for the
known root and require the user to choose a folder again. On a later process
start, an absent persisted grant is an unselected-root state.

Do not request `MANAGE_EXTERNAL_STORAGE`, legacy external-storage permission,
or Android media collection permissions.

## Alternatives considered

- Broad filesystem or media permissions: rejected because they exceed the
  least-privilege requirement and do not preserve provider portability.
- Copying selected media into application storage: rejected because large
  media must remain in place and a full-file cache would duplicate user data.
- Persisting raw filesystem paths: rejected because SAF providers need not
  expose stable or usable paths.

## Consequences

- Access is limited to folders the user explicitly chooses.
- The Android adapter owns URI construction and provider-specific behavior.
- Revocation or provider disappearance is a normal recoverable state.
- Root display names may be shown in the UI, but URIs and document ids are not
  written to normal logs or committed diagnostics.
- Provider traversal and playback remain testable behind app-owned interfaces.

## Validation / reversal criteria

The SM-T500 device test confirmed picker selection, nested enumeration,
persisted access after force-stop/relaunch, explicit release, repair UI, and
zero remaining persisted grant markers after a cold relaunch. Reverse this
decision only if a supported Android provider cannot satisfy required reads or
Android removes durable tree grants; any replacement must remain user-scoped
and avoid broad storage permission.

## References

- [Milestone 0 Android device validation](../manual-tests/milestone-0-android.md)
- [Android Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)
- [Milestone 0 risk-spike design](../superpowers/specs/2026-10-07-milestone-0-android-risk-spike-design.md)

