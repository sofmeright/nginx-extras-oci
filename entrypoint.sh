#!/bin/sh
set -e

# --- Refresh Cloudflare IP ranges (best effort) ---
mkdir -p /etc/nginx/cf
CF=/etc/nginx/cf/ips.conf
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL https://www.cloudflare.com/ips-v4 > "$tmp/ips-v4" || true
curl -fsSL https://www.cloudflare.com/ips-v6 > "$tmp/ips-v6" || true
{
  echo "# generated $(date -u +%FT%TZ)"
  [ -s "$tmp/ips-v4" ] && awk '{print "set_real_ip_from " $1 ";"}' "$tmp/ips-v4"
  [ -s "$tmp/ips-v6" ] && awk '{print "set_real_ip_from " $1 ";"}' "$tmp/ips-v6"
  echo "real_ip_header CF-Connecting-IP;"
} > "$CF"

# --- Ensure strong DH params (4096-bit) ---
DH=/etc/nginx/ssl/dhparam.pem
if [ ! -s "$DH" ]; then
  echo "Generating 4096-bit dhparam at $DH (this can take a while) ..."
  openssl dhparam -out "$DH" 4096
fi
# Validate bit size is >= 4096
if ! openssl dhparam -in "$DH" -text -noout 2>/dev/null | grep -q "DH Parameters: (4096 bit)"; then
  echo "Existing dhparam is not 4096-bit; regenerating..."
  openssl dhparam -out "$DH" 4096
fi
chmod 0644 "$DH"

exec "$@"