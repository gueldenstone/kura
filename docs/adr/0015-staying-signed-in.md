# 0015. Staying signed in: remember-me as the fallback for every request

- Status: Accepted
- Date: 2026-11-13

## Context
ADR 0004 kept remember-me so the phones stay signed in, and the browser pipeline has run the library's `sign_in_with_remember_me` before `load_from_session` since 2026-11-08. The phones still got signed out. Three reasons:

- The library's plug only tries the remember-me cookie when the session holds no token at all. A session token that stopped working (it runs out after 14 days, or was revoked) still counts as "signed in", so the cookie is skipped and the session is then dropped. This happens exactly when the installed app resumes: the LiveView reconnects with the old session, is sent to `/sign-in`, and that page loads with the same stale session, so the sign-in form shows.
- "Remember me" was unticked by default, so a quick sign-in on the phone never wrote the cookie.
- The remember-me token is never renewed, so everybody was signed out 30 days after signing in, however often they used the app.

## Decision
- `KuraWeb.Plugs.RememberMe` runs after `load_from_session` in the browser and offline pipelines. Without a signed-in user (no session token, or one that `load_from_session` rejected and dropped), it signs in from the remember-me cookie.
- When it does, it also writes a fresh remember-me cookie with a new 30-day token. Being signed out now takes 30 days without opening the app.
- The `remember_me` argument of the password sign-in defaults to true, so the checkbox starts ticked. It can still be unticked on a shared computer.

## Consequences
- Each renewal stores one more remember-me token. Renewals only happen when the session is lost or runs out, so there are only a few per phone each month. Expired tokens are cleaned up with the others.
- Signing out still deletes the cookie, and changing the password still signs out everywhere (`log_out_everywhere`).
- Requests with a working session do no extra work. A request without one tries the cookie and then checks the session once more.
