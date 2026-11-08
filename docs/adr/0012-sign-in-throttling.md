# 0012. Failed sign-ins lock the username for a while, counted in memory

- Status: Accepted
- Date: 2026-11-08

## Context
The sign-in page is on the public internet and passwords need only 8 characters (ADR 0004). Nothing limited how often a password could be tried, so a weak one could be guessed online. bcrypt makes each guess slower but does not cap them.

With sign-in tokens enabled, the password is checked inside the sign-in LiveView, not in an HTTP request, so a plug in the router never sees the attempts. Limiting by IP would also mean trusting `X-Forwarded-For` from Traefik.

## Decision
- Count failed password sign-ins **per submitted username** (case-insensitive), whether or not an account has it, so a lock says nothing about which usernames exist.
- After **10 failures within 15 minutes** the username is locked for **15 minutes**. A locked username is refused before its password is checked, even the right one, and the form says "Too many failed attempts. Try again in N min.". A successful sign-in clears the count.
- The check is `Kura.Accounts.User.Preparations.ThrottleSignIn`, an `around_transaction` hook on `sign_in_with_password`, so every way into that action is covered. The counts live in an ETS table owned by `Kura.Accounts.SignInThrottle`, which prunes old entries.

## Consequences
- A guesser gets about 40 tries an hour per username instead of as many as bcrypt allows.
- Someone who knows a username can keep it locked by failing on purpose. With two known people that is an annoyance, not a risk; remember-me keeps signed-in phones working (they do not sign in with a password).
- The counts are lost on a restart or deploy, and there is one counter per node. Both are fine for a single container (ADR 0009). Durable or distributed limits would need a table or a shared store.
