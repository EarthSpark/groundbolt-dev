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
| `sparknet-http/` | Distribution repo for the SparkNet-Http meter driver: publishes release binaries and builds the container image. The service source and `.proto` contract live elsewhere. |
| `ansible/` | Provisions a real GroundBolt host: `bootstrap_groundbolt.sh` runs on the target device, resolves config into `/etc/groundbolt/inventory.ini`, and runs `playbook.yml` locally to bring up the compose stack. |

## System shape

- The **ground webapp** manages a micro-grid. It talks to a **metering
  provider** over an OpenAPI HTTP+SSE contract (`METERING_PROVIDER_URL`); the
  provider drives the gateway radio that reaches the meters. The provider is
  `sparknet-http` (port 8080), which can run against a real gateway on a
  serial device or with `SPARKNET_HTTP_SIMULATE_GATEWAY=1` for dev.
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

Lives at `docker-compose.yml` in this directory — it's here because it spans
component repos: the webapp builds from `./thundercloud`, SymmetricDS from
`./symmetricds`, and `sparknet-http` is pulled as the published image (its
repo distributes prebuilt binaries; there's no source to build). Run compose
commands from the workspace root. Profiles:

- **default** — the ground stack: `ground` (webapp, http://localhost:8765),
  `postgres-ground` (host port 5440), `sparknet-http` (8080, gateway
  simulator on), `symds-ground`.
- **`--profile cloud`** — adds `cloud` (webapp, http://localhost:5010),
  `postgres-cloud` (5441), `symds-cloud` (31415). Only with this profile up
  does ground↔cloud sync run; without it `symds-ground` retries until the
  cloud side appears.

```sh
docker compose up -d                       # ground stack
docker compose --profile cloud up -d       # + cloud stack
docker compose exec ground uv run flask user create   # flask CLI
```

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
by `clone.sh` from the tracked `.env.example` when missing. It feeds both
the webapp containers (via `env_file:`) and compose interpolation, so
overrides (a specific site serial, real cloud SymmetricDS endpoint) also go
in it; the comments in `docker-compose.yml` document the variables.

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
