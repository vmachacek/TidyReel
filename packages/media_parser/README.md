# Media parser

Pure Dart local filename and directory parsing, adapted from the useful rules in
NormieRename's planner and the Pocket Cinema build specification. It performs no
network or filesystem operations and never changes media files.

`parseMediaName` returns title, series, inherited year, season, episode references,
and evidence or warnings. It recognizes standard and alternate episode markers,
natural-language markers, bounded ranges, chains, and strong season-folder context.
Suffixes such as `S06E11b` are retained and require review. Title-only episodes under
a show and season stay in that show without receiving an invented episode number.

`cleanMediaTitle` produces display text. `normalizedMediaTitle` produces a grouping
comparison key; the parsed year should be compared separately to distinguish remakes.
Localized names remain local evidence until provider aliases or user corrections
establish a canonical identity. Compatibility normalization covers common separators
and apostrophes; it does not implement complete Unicode NFKC normalization.

The real SpongeBob listing is copied unchanged into `test/fixtures` and asserts every
file's show, year, season, range membership, and suffix review behavior.
