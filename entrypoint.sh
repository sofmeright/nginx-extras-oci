#!/bin/sh
set -eu

CF_DIR="/etc/nginx/cf"
SSL_DIR="/etc/nginx/ssl"
DHPARAM="${SSL_DIR}/dhparam.pem"
DHPARAM_BITS="${DHPARAM_BITS:-4096}"
CF_REFRESH="${CF_REFRESH:-true}"   # set CF_REFRESH=false to skip
CF_TIMEOUT="${CF_TIMEOUT:-5}"

mkdir -p /var/run/nginx /var/cache/nginx /var/log/nginx

refresh_cf_ips() {
  [ "$CF_REFRESH" = "true" ] || return 0
  # Try to refresh; if it fails, keep any existing files
  curl -fsS --max-time "$CF_TIMEOUT" https://www.cloudflare.com/ips-v4 > "${CF_DIR}/ips-v4" || true
  curl -fsS --max-time "$CF_TIMEOUT" https://www.cloudflare.com/ips-v6 > "${CF_DIR}/ips-v6" || true

  {
    echo "# generated $(date -u +%FT%TZ)"
    if [ -f "${CF_DIR}/ips-v4" ]; then
      while read -r n; do [ -n "$n" ] && echo "set_real_ip_from $n;"; done < "${CF_DIR}/ips-v4"
    fi
    if [ -f "${CF_DIR}/ips-v6" ]; then
      while read -r n; do [ -n "$n" ] && echo "set_real_ip_from $n;"; done < "${CF_DIR}/ips-v6"
    fi
    echo "real_ip_header CF-Connecting-IP;"
  } > "${CF_DIR}/ips.conf"
}

ensure_dhparam() {
  if [ ! -s "$DHPARAM" ]; then
    echo "Generating DH parameters (${DHPARAM_BITS} bits)..." >&2
    tmp="${DHPARAM}.tmp"
    openssl dhparam -out "$tmp" "$DHPARAM_BITS"
    mv -f "$tmp" "$DHPARAM"
    chmod 0600 "$DHPARAM"
  fi
}

refresh_cf_ips || true
ensure_dhparam || true

# Validate config before launch
nginx -t

# Hand off to nginx as PID 1
exec "$@"