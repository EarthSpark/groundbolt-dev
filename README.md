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
| `thundercloud/` | The webapp (Python/Flask). Its own `docker-compose.test.yml` holds only the self-contained test harness that its CI runs. |
| `symmetricds/` | Docker image build for SymmetricDS, which syncs the ground and cloud databases bidirectionally. |
| `meter-driver-emulator/` | An emulator of the meter-driver HTTP+SSE contract. Runs in the local dev stack with `--profile driver-emulator`. |
| `sparknet-http/` | Distribution repo for the SparkNet-Http meter driver: release binaries plus its container image. Runs in the local dev stack with `--profile driver-sparknet`. |
| `ansible/` | Provisions a real GroundBolt host from a single bootstrap command run on the device. |

How they fit together: the ground webapp calls a meter driver over an
HTTP+SSE API to reach the meters (in local dev, `meter-driver-emulator` with
`--profile driver-emulator`, or `sparknet-http` in gateway-simulation mode with
`--profile driver-sparknet`); each of ground and cloud has its own Postgres, with a
SymmetricDS node beside each keeping the two databases in sync; the cloud
webapp is the same application pointed at the cloud database.

## Quickstart

Requires Docker Compose 2.24.0 or newer, the first release that accepts
`required: false` on `env_file` entries.

The local dev stack is this repo's `docker-compose.yml`. From the workspace
root:

```sh
docker compose --profile driver-emulator up -d   # ground stack + emulator driver: webapp at localhost:8765
docker compose -f docker-compose.yml -f docker-compose.cloud.yml --profile driver-emulator up -d
                                                 # + cloud stack: webapp at localhost:5010
```

To run with cloud without typing both `-f` flags, uncomment this line in
your `.env` (it is in the ground + cloud section of `.env.example`; an `.env`
created before that won't have it, so add it):

```sh
COMPOSE_FILE=docker-compose.yml:docker-compose.cloud.yml
```

Every `docker compose` command then uses both files, including `ps` and
`down`, which otherwise report the cloud containers as orphans. To run
ground on its own again, remove the line, or override it for one command
with `COMPOSE_FILE=docker-compose.yml docker compose ...` (a value exported
in the shell wins over `.env`).

Choose a meter driver with a profile, then register it in the ground app
under **Global Settings > Meter Drivers > Register driver**:

| Profile | Driver | Base URL to register |
|---|---|---|
| `--profile driver-emulator` | `meter-driver-emulator` | `http://meter-driver-emulator:18080` |
| `--profile driver-sparknet` | `sparknet-http` (gateway simulator on) | `http://sparknet-http:8080` |

With neither profile the stack runs without a meter driver; the webapp boots
normally with none registered.

### With cloud: ground gets its data from cloud

`docker-compose.yml` is the ground stack. `docker-compose.cloud.yml` adds the
cloud side (`cloud`, `postgres-cloud`, `symds-cloud`) and changes one thing
on ground: it stops ground from seeding its own database. If both sides
seeded, they would create the same ids for the same rows (the `admin` user,
config parameters), and when `symds-ground` first registered with
`symds-cloud`, cloud's initial load would overwrite ground's copies: ground
sessions logged out, anything configured on ground (a registered meter
driver) lost, and the System wallets duplicated. Starting cloud later would
not help; the overwrite happens whenever ground first registers.

So with the cloud file ground boots empty, as a production ground does: it
creates only its `ground` row and receives the admin, defaults and wallets
from cloud's initial load. Until that lands, typically one to two minutes
after `up`, ground has no user to log in with. To wait for it:

```sh
until docker compose exec -T postgres-ground psql -U spark -d ground -Atc 'select 1 from "user"' | grep -q 1; do sleep 5; done
```

The cloud file only affects a fresh ground database. A ground volume that was
already seeded on its own keeps its rows, so to switch a running ground-only
stack to cloud, start over with `down -v`:

```sh
docker compose -f docker-compose.yml -f docker-compose.cloud.yml --profile driver-emulator down -v
```

### Which images run

The webapp, SymmetricDS and meter-driver-emulator services name the `latest`
images that each component's CI publishes to GHCR from every build of `main`,
and each also has a `build` section pointing at its checkout. No
`pull_policy` is set, so Compose uses its default, `missing`: a plain `up`
runs whatever image of that name exists locally and pulls only when there is
none.

- The first `up` pulls the published `latest` images, so it needs only this
  repo checked out.
- `docker compose up -d --build` (after `./clone.sh`) builds the images from
  `./thundercloud`, `./symmetricds` and `./meter-driver-emulator`. The build
  carries the same image name, so later plain `up` runs keep using your local
  build.
- `up` never re-pulls `latest` on its own. `docker compose pull` fetches the
  newest published images and replaces a local build of the same name.
- A service whose image is not published yet fails to pull and is built from
  its checkout instead. On a fresh workspace, run `./clone.sh` first if an
  image is missing from the registry.

To build one component and pull the rest, name its services:

```sh
./clone.sh                            # clone/update all component repos
docker compose up -d --build ground   # build the webapp, pull everything else
docker compose build ground          # or build the webapp image (cloud uses it too) without starting it
```

`develop.watch` rebuilds (`docker compose watch`) also build from the
component's checkout, so they need `./clone.sh` too.

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
re-cloned, so the script is safe to run repeatedly. After either step the
script checks out the repo's submodules (`git submodule update --init
--recursive`); the meter-driver-emulator build needs its `meter-driver-spec`
submodule. Repos you can't access (private or unreachable with your current
SSH key) are **skipped** with a note — the run continues and exits
successfully. A repo whose submodule step fails is still cloned or updated
and is reported as `(<branch>; submodule update failed)`. A summary at the
end reports how many were cloned, updated, skipped, and had a failed
submodule step.

The script also seeds a local `.env` (the webapp's env file, read by
`docker-compose.yml`) from the tracked `.env.example` if you don't have one
yet; an existing `.env` is never touched. The `.env` is optional: without it
the webapp runs on the development defaults in `docker-compose.yml`, which
equal the `.env.example` values. For each variable, a value exported in the
shell that runs `docker compose` wins, then the value in `.env`, then the
default in `docker-compose.yml`. Compose also reads its own settings from
`.env`, such as `COMPOSE_FILE` to include `docker-compose.cloud.yml` (see
[Quickstart](#quickstart)).

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
