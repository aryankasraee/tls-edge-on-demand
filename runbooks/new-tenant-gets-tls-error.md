# Runbook: a new tenant gets a TLS error on first visit

> Owner: platform · Last verified: 2026-10-03 · Verified how: reproduced in the drill of this repo

## Symptoms

A customer's new domain fails the TLS handshake (`tlsv1 alert internal error`,
`ERR_SSL_PROTOCOL_ERROR`), while existing domains work.

## Impact

Only names that have never been served. Existing, cached domains are unaffected.

## Diagnose

1. Does DNS for the name point at the edge? If not, nothing here applies.
2. What did `ask` answer? Look for the name in the ask log:
   `docker compose logs ask | grep <domain>`.
   - `answer=403`: the name is not in the allowlist. Add it (see Mitigate).
   - no line at all: Caddy never reached `ask`. Check step 3.
3. Is `ask` up and reachable from Caddy? `docker compose ps ask`, and from the Caddy
   container: `wget -qO- http://ask:9000/check?domain=<domain>` (a `403` means it
   answers; a connection error means it does not).
4. Did the allowlist actually change? `ask` re-reads the file on every request, but a
   file replaced by an editor can leave a bind mount pointing at the old file.
   Append to the file, or restart `ask`.
5. Issuance itself failing (public CA): Caddy logs at `tls.obtain` show the CA's error.
   A rate-limit error means stop and wait; retrying makes it worse.

## Mitigate

- Missing from the allowlist: add the domain; the next request issues the certificate.
- `ask` down: start it. New names work again immediately; cached names were never affected.
- CA rate limit: do not retry in a loop. Wait for the window to reset, and find out
  what consumed the quota (an open `ask`, a restart storm, empty storage).

## Verify

`curl -sv https://<domain>/ 2>&1 | grep -E 'issuer:|SSL certificate verify'` shows a
verified certificate, and the ask log shows `answer=200` once for that name.

## Escalate

If issuance fails with a CA-side error that is not a rate limit, escalate to whoever
owns the CA account, with the `tls.obtain` log lines.

## Do not

- Switch `ask` to answer 200 for everything "just to unblock" a customer. That removes
  the only protection against a certificate-order flood.
- Restart every edge instance at once: with cold storage each name is a first request.
