# 0002. Ash with SQLite and AshAuthentication

- Status: Accepted
- Date: 2026-10-31

## Context
Kura is a self-hosted app on a single VPS for two users. Data volume is tiny. The project was generated with Phoenix 1.8, LiveView, Ash 3, `ash_sqlite` and `ash_authentication`.

## Decision
- Domain modelled with Ash resources and actions.
- SQLite via `ash_sqlite` as the only datastore (no Postgres server to operate).
- Username/password authentication via `ash_authentication`; two accounts sharing one household's data.

## Consequences
- Simple deployment and backups (a single database file).
- `ash_sqlite` supports fewer features than `ash_postgres`; check capabilities before relying on advanced queries.
- Moving to Postgres later is possible through the Ash data layer but would need a migration of data.
