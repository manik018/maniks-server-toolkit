# Release Artifacts

## Supported Artifact Format

Official Linux releases should be distributed as `tar.gz` archives when possible because tar preserves Unix executable metadata.

Build release archives with the project exclusion manifest so development-only artifacts are not shipped:

```bash
release_dir="$(mktemp -d "${TMPDIR:-/tmp}/mst-release.XXXXXX")"
tar --sort=name --mtime='UTC 2026-07-18' --owner=0 --group=0 --numeric-owner \
  --pax-option=delete=atime,delete=ctime \
  --exclude-from=release.exclude \
  -czf "${release_dir}/mst-release.tar.gz" .
```

The `release.exclude` manifest removes temporary test output, local logs/caches, editor backups, Python cache files, and release staging leftovers while preserving runtime files, scripts, tests, documentation, schemas, license, and changelog.

## Executable Metadata Restoration

If an archive format or upload path strips executable bits, restore only MST's canonical executable files:

```bash
bash scripts/restore-executable-bits.sh
```

The restoration helper is intentionally allowlist-based. It updates only:

- `mst`
- `install.sh`
- `uninstall.sh`
- `scripts/release-check.sh`
- `scripts/restore-executable-bits.sh`
- `scripts/shellcheck.sh`
- `tests/test_runner.sh`

It does not recursively chmod the repository and does not modify library, module, renderer, inspector, configuration, schema, or documentation files.
