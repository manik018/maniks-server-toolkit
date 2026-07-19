# Troubleshooting

## Doctor command

Run:

```bash
mst doctor
```

## Common issues

- `mst doctor` reports missing dependencies: install the missing required binaries before proceeding.
- Logging sink is not writable: run `mst doctor` as a user with access to the configured log directory or install MST normally.
- `mst` commands show `NOT IMPLEMENTED`: this is expected during the foundation implementation phase for non-foundation commands.
