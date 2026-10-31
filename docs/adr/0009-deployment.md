# 0009. Deployment: one Docker image, SQLite on a volume

- Status: Accepted
- Date: 2026-10-31

## Context
Kura runs on the owner's VPS in a Docker container behind Traefik, which terminates TLS. The data is one SQLite file (ADR 0002), so there is exactly one instance and the file has to survive container replacement.

## Decision
- A multi-stage `Dockerfile` builds an Elixir release on Debian and runs it as `nobody`. The build image versions are build args and match CI.
- The database path comes from `DATABASE_PATH` (`/data/kura.db` on a volume), not a URL. `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET` and `PHX_HOST` are required in production.
- The container's `bin/server` migrates the database, then starts the app, so a new image never runs against an old schema.
- Accounts are created inside the running container: `bin/kura eval 'Kura.Release.create_user("name", "password")'` (the release has no Mix).
- GitHub Actions (`.github/workflows/ci.yml`) checks formatting, warnings and tests, builds the image on every pull request and pushes it to ghcr.io from `main` (tag `main`) and from `v*` tags (tags `stable` and the version).
- Dependabot proposes Mix, Docker and Actions updates weekly.

## Consequences
- Only one container may use the volume at a time (SQLite single writer); no rolling deploys.
- Backups, Traefik labels and the way the host pulls the image are the host's concern and are not part of this repository.
