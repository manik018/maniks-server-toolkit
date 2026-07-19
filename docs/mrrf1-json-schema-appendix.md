# MRRF1 JSON Schema Appendix

Schema path:

- `schemas/mrrf1.schema.json`

Schema standard:

- JSON Schema Draft 2020-12

Stable schema identifier:

- `https://schemas.mst.local/mrrf1/v1/mrrf1.schema.json`

## Scope

This appendix defines the exact JSON representation of MRRF1 for machine-readable output. It supports:

- a single individual check result
- a multi-record aggregate report

## Top-Level Object

The top-level object is a document envelope.

Required fields:

- `schema_version`
- `document_type`
- `generated_at`
- `records`

Optional fields:

- `toolkit`
- `toolkit_version`
- `command`
- `host`
- `aggregate`
- `exit_code`

`additionalProperties` is `false`.

## Core Field Invariants

- `schema_version` is always integer `1`
- `document_type` is `result` or `report`
- `generated_at` is RFC 3339 UTC-compatible `date-time`
- `records` is an array of result records
- `document_type=result` requires exactly one record
- `document_type=report` requires an `aggregate` object

## Result Record Fields

Required fields on every record:

- `result_id`
- `module`
- `check`
- `target`
- `status`
- `severity`
- `score`
- `summary`
- `details`
- `recommendations`
- `metadata`
- `errors`
- `duration_ms`
- `observed_at`

### Status

Allowed values:

- `ok`
- `warn`
- `critical`
- `unknown`
- `unavailable`
- `skipped`

Meaning:

- `unknown`: a check was attempted but the result could not be determined reliably
- `unavailable`: the check could not be performed because access, support, or dependency conditions were not met
- `skipped`: the check was intentionally not run by policy or command scope

### Severity

Allowed values:

- `ok`
- `warning`
- `critical`
- `unknown`

### Score

Decision:

- `score` may be `null`

Rules:

- `0-100` integer when a meaningful score exists
- `null` for `unavailable` and `skipped`
- `unknown` may still carry a conservative numeric score if policy defines one

### Summary

- single-line only
- maximum length `200`
- control characters prohibited
- multiline text is forbidden

### Details

`details` is an array of bounded key/value objects.

Constraints:

- max `64` entries
- key format is fixed
- value type is explicit
- string values are max `256`
- control characters are prohibited
- `redacted=true` marks that the stored value is intentionally masked

No arbitrary shell fragments or multiline blobs are permitted.

### Recommendations

`recommendations` is an array of structured objects, not freeform paragraphs.

Constraints:

- max `16` entries
- `summary` max `200`
- `priority` is `low|medium|high`
- `manual_action` states whether operator intervention is required

### Metadata

`metadata` is deliberately constrained.

Required fields:

- `source`
- `provenance`
- `privilege_requirement`
- `contains_sensitive_data`
- `redactions_present`
- `optional_dependencies`

Rules:

- `contains_sensitive_data` is always `false`
- provenance is descriptive and sanitized
- privilege requirement is explicit
- optional dependencies are structured, bounded records

### Errors

One result may contain multiple errors.

This is intentional because:

- a single check may hit more than one degraded condition
- implementation should not collapse distinct causes into one vague message

Error categories:

- `warning`
- `critical`
- `permission`
- `timeout`
- `network`
- `configuration`
- `dependency`
- `internal`
- `unknown`

## Aggregate Report Object

The aggregate object supports report documents.

Required fields:

- `record_count`
- `overall_status`
- `overall_severity`
- `overall_score`
- `risk_level`
- `module_summaries`

This allows aggregate reporting without inventing an incompatible top-level structure.

## Redaction Representation

Redaction is represented explicitly:

- `details[].redacted = true`
- `metadata.redactions_present = true`

Sensitive raw values are not allowed in the schema contract.

## Provenance Representation

Provenance is represented by:

- `metadata.source`
- `metadata.provenance`

This shows both source class and concise origin description.

## Privilege Requirement Representation

Represented by:

- `metadata.privilege_requirement`

Allowed values:

- `none`
- `elevated_read`
- `root_only_path`
- `network_only`

## Optional Dependency Representation

Represented by:

- `metadata.optional_dependencies[]`

Each dependency entry records:

- name
- whether it is required for the specific check path
- whether it was available

## Valid Examples

Healthy example:

- `schemas/examples/valid-healthy.json`

Warning example:

- `schemas/examples/valid-warning.json`

Unavailable-permission example:

- `schemas/examples/valid-unavailable-permission.json`

Timeout example:

- `schemas/examples/valid-timeout.json`

Aggregate report example:

- `schemas/examples/valid-aggregate-report.json`

## Invalid Examples

Multiline summary:

- `schemas/examples/invalid-multiline-summary.json`

Why invalid:

- summary contains a forbidden newline control character

Unavailable record with numeric score:

- `schemas/examples/invalid-unavailable-score.json`

Why invalid:

- `status=unavailable` requires `score=null`

