# GroundBolt dev workspace

This is a metarepo: it tracks only the `repos` manifest, `clone.sh`, and docs.
The component repos are cloned by `clone.sh` into subfolders of this directory
and are **independent git repos**, all gitignored here.

## Workspace rules

- **Nested git repos.** `git` commands at the workspace root touch only the
  metarepo. Changes to component code are committed inside that component's
  folder (`thundercloud/`, `symmetricds/`, etc.), each against its own origin.
- **Everyone works on `main`** in every repo — trunk-based development.
- **The manifest is the source of truth.** To add/remove a component, edit
  `repos` and re-run `./clone.sh`. The script clones missing repos and
  fast-forwards existing ones; repos your SSH key can't reach are skipped.
- **Sibling layout is guaranteed.** Cross-repo tooling in this metarepo may
  assume every component is a direct subfolder of this directory. Tooling
  inside a component repo may not — a component can be cloned anywhere.
- **The `.gitignore` is a whitelist.** It ignores `/*` and un-ignores tracked
  files one by one. A new file tracked by the metarepo needs its own `!/name`
  entry or git will not see it.

## One codebase, three names

The webapp in `thundercloud/` is the `sparkmeter` Python package. Deployed to
the cloud it's called **ThunderCloud**; deployed to a base station on the
ground it's called **GroundBolt**. Same code, different deployment target.

## Components

| Folder | What it is |
|---|---|
| `thundercloud/` | The webapp (Python/Flask, managed with `uv`). Carries no dev compose file — only `docker-compose.test.yml`, the self-contained test harness its CI runs. |
| `symmetricds/` | Docker image build for SymmetricDS, the bidirectional DB-sync engine between the ground and cloud Postgres databases. Configured via env vars (`ENGINE_NAME`, `GROUP_ID`, `REGISTRATION_URL`, …); see its README. |
| `meter-driver-emulator/` | An emulator of the meter-driver HTTP+SSE contract (port 18080). Runs in the local dev stack with `--profile driver-emulator`. Its Docker build copies the `meter-driver-spec` submodule. |
| `sparknet-http/` | Distribution repo for the SparkNet-Http meter driver: publishes release binaries and builds the container image. The service source and `.proto` contract live elsewhere. Runs in the local dev stack with `--profile driver-sparknet`. |
| `ansible/` | Provisions a real GroundBolt host: `bootstrap_groundbolt.sh` runs on the target device, resolves config into `/etc/groundbolt/inventory.ini`, and runs `playbook.yml` locally to bring up the compose stack. |

## System shape

- The **ground webapp** manages a micro-grid. It talks to a **meter
  driver** over an OpenAPI HTTP+SSE contract; the driver reaches the meters.
  Drivers are registered from the running ground app under Global Settings >
  Meter Drivers > Register driver by the base URL of their HTTP service. In
  the local dev stack a driver runs only when its profile is chosen:
  `--profile driver-emulator` runs `meter-driver-emulator`, registered as
  `http://meter-driver-emulator:18080`; `--profile driver-sparknet` runs
  `sparknet-http` (port 8080), registered as `http://sparknet-http:8080`,
  which can run against a real gateway on a serial device or with
  `SPARKNET_HTTP_SIMULATE_GATEWAY=1`. With neither profile the stack runs
  without a driver and the webapp boots normally with none registered.
- Each side (ground, cloud) has its own Postgres. A **SymmetricDS node runs
  next to each database** (`symds-ground`, `symds-cloud`) and the pair syncs
  them bidirectionally. `GROUP_ID` values must match the node-group link
  configured in `sparkmeter.database.sync` (`ground-group` → `cloud-group`).
- The **cloud webapp** is the same image as the ground webapp, pointed at the
  cloud database.
- In production (ansible), each component is its own compose project joined by
  the shared external Docker network `sparkapp`; services reach each other by
  service name across projects, with no cross-project `depends_on`.

## Local dev stack

Lives at `docker-compose.yml` (the ground stack) and
`docker-compose.cloud.yml` (adds the cloud side) in this directory — it's here
because it spans component repos. Requires Docker Compose 2.24.0 or newer,
the first release that accepts `required: false` on `env_file` entries (it
is the first built on compose-go v2.0.0-beta.3, which added it; 2.23.3 used
compose-go v1.20.2). Run compose commands from the workspace root.

Images: the webapp (`ground`, `cloud`), SymmetricDS (`symds-ground`,
`symds-cloud`) and `meter-driver-emulator` name
`ghcr.io/earthspark/{thundercloud,symmetricds,meter-driver-emulator}:latest`,
which each component's CI publishes from every build of `main` (a release
tag never moves `latest`). Each also keeps a `build` section. No
`pull_policy` is set, so Compose's default, `missing`, applies: a plain `up`
runs whatever image of that name exists locally and pulls only when it is
absent.

- The first `up` pulls the published `latest`, so it needs only the metarepo.
- `docker compose up --build` builds from the `./thundercloud`,
  `./symmetricds` and `./meter-driver-emulator` checkouts, which `clone.sh`
  provides (with submodules; the emulator's build needs `meter-driver-spec`).
  The build carries the same image name, so later plain `up` runs keep using
  it.
- Nothing re-pulls `latest` on its own. `docker compose pull` fetches the
  newest published images and replaces a local build of the same name.
- A service whose image is not published yet fails to pull and falls back to
  building from its checkout, so on a fresh workspace run `./clone.sh` first
  if an image is missing from the registry.
- To build one component and pull the rest: `docker compose up -d --build
  ground`, or `docker compose build ground` (`cloud` uses the same image).
  `develop.watch` rebuilds also need that component's checkout from
  `./clone.sh`.

Profiles and the cloud file:

- **default** — the ground stack: `ground` (webapp, http://localhost:8765),
  `postgres-ground` (host port 5440), `symds-ground`. No meter driver.
- **`--profile driver-emulator`** — adds `meter-driver-emulator` (18080).
  Register it as `http://meter-driver-emulator:18080`.
- **`--profile driver-sparknet`** — adds `sparknet-http` (8080, gateway
  simulator on), pulled as the published
  `ghcr.io/earthspark/sparknet-http:latest` image (its repo distributes
  prebuilt binaries; there's no source to build). Register it as
  `http://sparknet-http:8080`.
- **`-f docker-compose.yml -f docker-compose.cloud.yml`** — adds `cloud`
  (webapp, http://localhost:5010), `postgres-cloud` (5441), `symds-cloud`
  (31415), and makes `ground` boot without seeding itself so it gets its
  data from cloud's initial load, as a production ground does. Only with
  this file does ground↔cloud sync run; without it `symds-ground` retries
  until the cloud side appears. `cloud` `extends` the base file's `ground`
  service, overriding only its database, ports and `SM_HEROKU`. Ground must
  not seed itself here: both sides would seed the same ids and cloud's
  initial load would overwrite ground's rows and duplicate the System
  wallets (see the file's header). Needs a fresh ground volume (`down -v`).

```sh
docker compose --profile driver-emulator up -d   # ground stack + emulator
docker compose -f docker-compose.yml -f docker-compose.cloud.yml --profile driver-emulator up -d  # + cloud stack
docker compose exec ground uv run flask user create   # flask CLI
```

`COMPOSE_FILE=docker-compose.yml:docker-compose.cloud.yml` in `.env`
(commented out in `.env.example`'s ground + cloud section) makes
every `docker compose` command use both files, so `ps`/`down` see the cloud
containers too. To run ground alone again, remove it or override it for one
command with `COMPOSE_FILE=docker-compose.yml docker compose ...` (the shell
wins over `.env`).

The **test harness is not here**: it stays self-contained in
`thundercloud/docker-compose.test.yml` because thundercloud's CI
(`scripts/run_coverage.sh`) runs it with only that repo checked out. Run
tests from `thundercloud/`:

```sh
cd thundercloud
docker compose -f docker-compose.test.yml run --rm test                      # all tests
docker compose -f docker-compose.test.yml run --rm test uv run pytest <path> # subset
```

The webapp's `.env` lives at the workspace root: local (gitignored), seeded
by `clone.sh` from the tracked `.env.example` when missing, and optional —
`env_file` sets `required: false`. The webapp's development defaults live in
the `x-webapp-environment` block of `docker-compose.yml` as `${VAR:-default}`
entries equal to the `.env.example` values. For each variable, a value
exported in the shell that runs compose wins, then `.env`, then the compose
default. The `.env` feeds both the webapp containers (via
`env_file:`) and compose interpolation, so overrides (a specific site serial,
real cloud SymmetricDS endpoint) also go in it; the comments in
`docker-compose.yml` document the variables. Compose also reads its own
settings from `.env`, such as `COMPOSE_FILE` to include
`docker-compose.cloud.yml`.

Non-Docker local dev (uv, flask CLI, database reset, demo data) is covered in
`thundercloud/README.md`.

## Conventions in thundercloud

- Python deps are managed by `uv`; dev deps are in `[dependency-groups] dev`.
  Sync with `uv sync --group dev`. Prefix commands with `uv run`.
- DB schema migrations are Alembic, created via
  `docker compose exec ground uv run flask database new-revision "<desc>"`
  and living in `sparkmeter/alembic/versions/`.
- Coding style: `thundercloud/CodingStyle.md`; contribution flow:
  `thundercloud/CONTRIBUTING.md`.
