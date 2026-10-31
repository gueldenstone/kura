# Architecture Decision Records

We record significant decisions as ADRs, written when the decision is made.

- One file per decision: `NNNN-short-title.md`, numbered sequentially.
- Statuses: `Proposed`, `Accepted`, `Superseded by NNNN`, `Rejected`.
- Never rewrite an accepted ADR's decision; supersede it with a new ADR.

Template:

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
## Decision
## Consequences
```

## Index

| # | Title | Status |
|---|-------|--------|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-ash-sqlite-stack.md) | Ash with SQLite and AshAuthentication | Accepted |
| [0003](0003-pwa-offline-strategy.md) | PWA with offline reads and queued check-offs | Accepted |
| [0004](0004-username-password-auth-no-registration.md) | Username/password auth without registration | Accepted |
| [0005](0005-item-stock-model.md) | Items with per-item stock tracking in one resource | Accepted |
| [0006](0006-visual-design.md) | Visual design: market stall light, dark chocolate dark | Accepted |
| [0007](0007-shopping-list-model.md) | Shopping list model and live sync | Accepted |
| [0008](0008-offline-implementation.md) | How offline works | Accepted |
