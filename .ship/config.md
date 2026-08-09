# ship pipeline profile

This repository's resolved delivery pipeline, read by the `ship` skill before it
touches the working tree. Edit it directly; ship rewrites it only when one of
these commands stops resolving.

```markdown
verify: bin/scan-skills.sh && bin/sync-versions.sh   # asked
base: main
release: none
post-merge: none
```

Detection alone would find only `bin/scan-skills.sh`, because that is the sole
command the README names as a pre-commit gate and the only one CI runs.
`bin/sync-versions.sh` is just as much a gate - it fails when a skill directory
is claimed by no plugin entry, by more than one, or is claimed but missing - so
it is recorded here rather than left to be rediscovered.
