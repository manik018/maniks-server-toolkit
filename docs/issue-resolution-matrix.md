# Issue Resolution Matrix

| Engineering Review Issue | How It Was Solved | Where It Was Solved | Fully Resolved |
|---|---|---|---|
| No formal result schema contract | Introduced `MRRF1`, a mandatory line-oriented normalized internal result model with explicit fields, escaping, null rules, and error fields | `docs/architecture-design-document.md` sections 8 and 18 | Yes |
| Architecture over-layered for Bash | Simplified architecture to core libraries, inspectors, policy/rendering, commands | sections 3, 4, 5, 20 | Yes |
| Bootstrap and dependency architecture not aligned | Added deterministic runtime loading model and explicit import rules | section 7 | Yes |
| Privilege escalation path underspecified | Removed self-escalation entirely and defined explicit operator-invoked elevated mode | sections 10 and 11 | Yes |
| Cron architecture too coarse | Added lock model, overlap handling, stale lock recovery, partial execution model, power failure behavior | section 21 | Yes |
| Configuration model mixed concerns | Partitioned config into runtime, inventory, policy, delivery, presentation | section 15 | Yes |
| Multi-target architecture only partially designed | Explicitly scoped MST to a single-host toolkit with optional small inventories | sections 15.3 and 31 | Yes |
| Output contract too human-first | Made JSON first-class architecturally and separated internal data from rendering | sections 14 and 19 | Yes |
| Installer upgrade semantics underspecified | Added installer modes and upgrade requirements | section 26 | Yes |
| Uninstaller data retention ambiguity | Classified artifacts and defined default vs optional cleanup | section 27 | Yes |
| Doctor risked becoming a god command | Split doctor into bounded internal categories | section 24 | Yes |
| Release model lacked compatibility policy | Added explicit compatibility guarantees | section 29 | Yes |
| `lib/telemetry-none` placeholder awkward | Removed entirely | sections 3, 5, architecture change log | Yes |
| `assets/` had no clear need | Removed from required architecture | section 5, architecture change log | Yes |
| `command.config` undefined | Defined as `mst config show` within CLI contract | section 10 | Yes |
| Report/recommend naming inconsistency | Replaced multi-engine naming with `policy` plus renderers | sections 3 and 20 | Yes |
| Temperature support underspecified | Kept as best-effort within health inspector behavior and unknown/unavailable model | sections 8, 24 | Yes |
| Optional service scoring ambiguity | Policy library now owns scoring over normalized records and optional services can be encoded consistently within one schema-governed record model | sections 8, 20, and 24 | Yes |
| Optional Unicode output underspecified | Output model now standardizes text rendering and does not depend on Unicode semantics | section 19 | Yes |
| Privileged re-entry security risk | Removed from architecture | sections 10 and 11 | Yes |
| TOCTOU risk under-acknowledged | Added filesystem safety categories and residual risk statement | section 16 | Yes |
| Cron abuse risk | Added locks, overlap handling, stale lock detection, partial execution controls | section 21 | Yes |
| Secret handling incomplete | Added dedicated secret lifecycle rules | sections 15.4 and 23.3 | Yes |
| Command execution wrapper underspecified | Added mandatory wrapper contract and security rules | section 17 | Yes |
| Need machine-readable output as first-class contract | Added JSON rendering as first-class architecture | sections 10, 19, 29 | Yes |
| Exact MRRF1 JSON schema appendix missing | Added authoritative Draft 2020-12 schema, examples, and appendix documentation | `schemas/mrrf1.schema.json`, `docs/mrrf1-json-schema-appendix.md` | Yes |
| Exact lockfile metadata appendix missing | Added exact `flock`-authoritative lock metadata contract and concurrency truth table | `docs/lockfile-metadata-appendix.md`, section 21 | Yes |
