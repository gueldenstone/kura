# 0004. Username/password auth without registration

- Status: Accepted
- Date: 2026-10-31

## Context
Kura has exactly two users who share one household's data. The app is self-hosted and has no email delivery. The generated `ash_authentication` setup used magic links with open registration.

## Decision
- Sign in with a **username** and password (`ash_authentication` password strategy, `identity_field :username`); remember-me stays so phones remain signed in.
- **No registration**: `registration_enabled? false`, no register/reset/confirm/magic-link routes, no email senders.
- Accounts are created by the owner with `mix kura.user.create USERNAME`, which calls the `:create` action (not reachable from the web).
- Passwords need at least 8 characters.
- Usernames are `ci_string`. SQLite has no real `citext`, so the unique index is case-sensitive; case-insensitive uniqueness comes from the identity's `pre_check?`. That is race-prone in theory and fine for two accounts.
- The initial users migration was regenerated rather than amended, because nothing had been deployed.

## Consequences
- No password reset: a forgotten password is fixed by the owner on the server (a future `mix` task if needed).
- Adding a third person later means running the mix task; no invitation flow.
- Sign-out is `DELETE /sign-out` (one tap from the header); `GET /sign-out` is the library's confirmation page.
