# GroundBolt dev workspace

The dev workspace metarepo. It pulls together the component repos you work on
into one folder so you can build and run the system locally.

The whole mechanism is two files:

- `repos` — a plain-text manifest listing each component repo (`name url [branch]`).
- `clone.sh` — clones or updates every repo in the manifest.

Because every component is cloned as a direct subfolder, tooling in this repo
can rely on that layout — something no individual component repo can assume
about its siblings.

## What's in the workspace

One codebase, three names: the webapp in `thundercloud/` is the `sparkmeter`
Python package — called **ThunderCloud** when deployed to the cloud and
**GroundBolt** when deployed to a base station on the ground.

| Folder | What it is |
|---|---|
| `thundercloud/` | The webapp (Python/Flask). Its own `docker-compose.yml` holds only the self-contained test harness that its CI runs. |
| `symmetricds/` | Docker image build for SymmetricDS, which syncs the ground and cloud databases bidirectionally. |
| `sparknet-http/` | Distribution repo for the SparkNet-Http meter driver: release binaries plus the container image the ground webapp talks to for meter operations. |
| `ansible/` | Provisions a real GroundBolt host from a single bootstrap command run on the device. |

How they fit together: the ground webapp calls the metering provider
(`sparknet-http`, run in gateway-simulation mode in local dev) over an
HTTP+SSE API to reach the meters; each of ground and cloud has its own
Postgres, with a SymmetricDS node beside each keeping the two databases in
sync; the cloud webapp is the same application pointed at the cloud database.

## Quickstart

The local dev stack is this repo's `docker-compose.yml`: it builds the webapp
from `./thundercloud` and SymmetricDS from `./symmetricds`, and pulls the
published `sparknet-http` image. From the workspace root:

```sh
./clone.sh                            # clone/update all component repos
docker compose up -d                  # ground stack: webapp at localhost:8765
docker compose --profile cloud up -d  # + cloud stack: webapp at localhost:5010
```

Tests stay self-contained in thundercloud (its CI runs them with no sibling
checkouts):
`cd thundercloud && docker compose -f docker-compose.test.yml run --rm test`.
See `thundercloud/README.md` for the full development guide (including
non-Docker local development) and each component repo's README for its own
details.

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

The script also seeds a local `.env` (the webapp's env file, read by
`docker-compose.yml`) from the tracked `.env.example` if you don't have one
yet; an existing `.env` is never touched.

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
