#!/usr/bin/env bash
# Prove the on-demand TLS edge behaves the way the README claims, including the
# uncomfortable cases (cached certs outlive the allowlist; ask outage fails closed;
# an open ask endpoint issues for anything).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p results

ROOT=/caddy-data/caddy/pki/authorities/local/root.crt
cp tenants.txt /tmp/tenants.orig
trap 'cat /tmp/tenants.orig > tenants.txt; ASK_MODE=allowlist docker compose up -d ask >/dev/null 2>&1 || true' EXIT

IP=""
c() { docker compose exec -T client curl "$@"; }
caddy_ip() { [[ -n "$IP" ]] || IP=$(docker compose exec -T client getent hosts caddy | cut -d' ' -f1); echo "$IP"; }

# prints: ok (verified cert, 200) or refused (handshake failed)
tls() {
  local host=$1
  if c -s -o /dev/null --max-time 10 --cacert "$ROOT" --resolve "$host:443:$(caddy_ip)" "https://$host/" 2>/dev/null; then
    echo ok
  else
    echo refused
  fi
}
issued() { docker compose logs caddy --no-log-prefix 2>&1 | grep -c '"msg":"certificate obtained successfully"' || true; }

fail=0
expect() { # description, want, got
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1 (wanted $2, got $3)"; fail=1; fi
}

docker compose up -d >/dev/null
for _ in $(seq 1 30); do [[ -n "$(docker compose exec -T client getent hosts caddy 2>/dev/null)" ]] && break; sleep 1; done

echo "== allowlist mode"
expect "listed tenant gets a verified certificate on first request" ok "$(tls acme.example)"
issuer=$(c -sv --max-time 10 --cacert "$ROOT" --resolve "acme.example:443:$(caddy_ip)" https://acme.example/ 2>&1 | grep -c 'issuer: CN=Caddy Local Authority' || true)
expect "the certificate was issued by the lab CA" 1 "$issuer"
expect "unlisted domain is refused at the handshake" refused "$(tls evil.example)"

echo "new tenant appears without a restart"
expect "not yet listed" refused "$(tls newshop.example)"
echo "newshop.example" >> tenants.txt   # append keeps the inode, so the bind mount sees it
expect "listed now, served on next request" ok "$(tls newshop.example)"

echo "removal does not revoke what was already issued"
grep -v '^newshop.example$' /tmp/tenants.orig > /tmp/tenants.new; cat /tmp/tenants.new > tenants.txt
expect "removed tenant is still served from the cache" ok "$(tls newshop.example)"

echo "ask outage fails closed for new names only"
echo "later.example" >> tenants.txt
docker compose stop ask >/dev/null
expect "new name cannot be issued while ask is down" refused "$(tls later.example)"
expect "cached name keeps working while ask is down" ok "$(tls acme.example)"
docker compose start ask >/dev/null; sleep 2
expect "new name works once ask is back" ok "$(tls later.example)"

echo "random names against the allowlist"
before=$(issued)
for i in $(seq 1 30); do tls "rand-$i.example" >/dev/null; done
allow_issued=$(( $(issued) - before ))
expect "30 random names cause 0 issuances" 0 "$allow_issued"

echo "== open mode (the mistake this repo exists to show)"
ASK_MODE=open docker compose up -d ask >/dev/null; sleep 3
before=$(issued)
for i in $(seq 1 30); do tls "flood-$i.example" >/dev/null; done
open_issued=$(( $(issued) - before ))
expect "30 random names cause 30 issuances" 30 "$open_issued"
echo "   (against a public CA each of those is a new order counted toward its rate limit)"

jq -n --argjson allow "$allow_issued" --argjson open "$open_issued" \
  '{random_names_tried:30, issuances_with_allowlist:$allow, issuances_with_open_ask:$open}' | tee results/drill.json
exit $fail
