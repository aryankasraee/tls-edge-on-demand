# tls-edge-on-demand

A multi-tenant HTTPS edge that gets a certificate for a customer's domain **the
first time someone visits it**, and refuses to do so for names it was never told
about. It is built with [Caddy](https://caddyserver.com) on-demand TLS and a small
`ask` service, and it comes with a drill that proves the behaviour, including the
parts that surprise people.

```
client ──TLS handshake (SNI: shop.customer.com)──▶ Caddy
                                                    │ never seen this name?
                                                    ▼
                                      GET ask:9000/check?domain=shop.customer.com
                                                    │ 200 = go ahead, otherwise refuse
                                                    ▼
                                           issue certificate, cache it, serve
```

## Why `ask` exists

On-demand TLS means anyone who can point a name at your edge, or just send a TLS
handshake with a made-up server name, can make you **request a certificate**. Against
a public CA that is an attack on your own rate limits: enough made-up names and
real customers can no longer get certificates. The `ask` endpoint is the gate. Open
it (answer 200 to everything) and you have no gate.

## Run it

```bash
make test    # unit tests for the ask service
make up      # start ask + Caddy + a curl client
make drill   # the proof
make down
```

Needs Docker with Compose v2, `jq`, and `python3`. The lab uses Caddy's built-in CA so
it runs offline; with a public ACME CA the mechanism is the same.

## What the drill proves

| Claim | Result |
|---|---|
| A listed tenant gets a verified certificate on its first request | yes |
| An unlisted name is refused at the TLS handshake | yes |
| Adding a tenant needs no restart (the file is re-read on each check) | yes |
| **Removing a tenant does not revoke its certificate**: it is served from cache | yes (a surprise) |
| If `ask` is down, **new** names cannot be issued, cached names keep working | yes (fails closed) |
| 30 random names against the allowlist cause issuances | **0** |
| 30 random names against an open `ask` cause issuances | **30** |

The last two rows are the whole point: the same flood, with and without the gate.

## Things to know before production

- **`internal` is lab-only.** Remove it from the Caddyfile and a public ACME CA issues
  the certificates.
- **`ask` is on the critical path for new names.** If it is down, new customers see
  TLS errors. Run more than one copy and alert on it. It does not affect names that
  are already cached.
- **Removing a tenant is not revocation.** The certificate stays valid and cached.
  If you must cut a tenant off, also stop routing its traffic, and revoke explicitly.
- **Share certificate storage between edge replicas**, or each replica orders its own
  certificate for every name and multiplies your CA usage.
- **Cold start.** After a restart with empty storage every name is a first request.
  Persist storage, and do not restart the whole fleet at once.
- Caddy's image tag is pinned to `2.11.6-alpine`, the newest published on Docker Hub
  when this was written.

## Runbook

- [`runbooks/new-tenant-gets-tls-error.md`](runbooks/new-tenant-gets-tls-error.md)

## License

MIT
