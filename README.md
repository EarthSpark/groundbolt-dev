# GroundBolt dev workspace

The dev workspace metarepo. It pulls together the component repos you work on
into one folder so you can build and run the system locally.

The whole mechanism is two files:

- `repos` — a plain-text manifest listing each component repo (`name url [branch]`).
- `clone.sh` — clones or updates every repo in the manifest.

## Usage

```sh
./clone.sh
```

This clones (or updates) every repo you can access. Each reachable repo is
cloned on `main`; if it's already present, it's fast-forwarded instead of
re-cloned, so the script is safe to run repeatedly. Repos you can't access
(private or unreachable with your current SSH key) are **skipped** with a
note — the run continues and exits successfully. A summary at the end reports
how many were cloned, updated, and skipped.

## Workflow

- **Everyone works on `main`** — trunk-based development keeps the set of
  components integrated.
- **The manifest is the source of truth.** To add a repo, append a line to
  `repos`; to remove one, delete its line. Then re-run `./clone.sh`.

## Manifest format

One repo per line:

```
name  url  [branch]
```

- `name` — the local directory to clone into.
- `url` — the clone URL (SSH; you clone what your key can reach).
- `branch` — optional; defaults to `main`.

Blank lines and lines starting with `#` are ignored.
