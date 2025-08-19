# nginx-extras-oci
NGINX on Alpine with the “extras” module installed. 
There are probably other containers like this but this is the one I run.

Features:
- Dynamic modules: headers-more, brotli (filter + static), geoip2, echo
- Private health endpoint baked in
- Cloudflare real client IP auto-refresh at startup
- Strict TLS defaults (HSTS on), compression enabled
- Minimal, production-friendly entrypoint

**Image**: prplanit/nginx-extras-oci:latest
**Base**: alpine:3.22.1

## Contents
- Dockerfile (core)
- Installs nginx, ca-certificates, curl, tzdata, openssl
- Adds modules: nginx-mod-http-brotli, nginx-mod-http-echo, nginx-mod-http-geoip2, nginx-mod-http-headers-more
- Loads modules from /etc/nginx/modules.d/
- Health server baked at 127.0.0.1:8080 → /healthz
- Copies nginx.conf (defaults + includes), and entrypoint.sh
- Exposes 80/443; STOPSIGNAL SIGQUIT

## entrypoint.sh (behavior)
At container start:
1. Refresh Cloudflare IPs → writes /etc/nginx/cf/ips.conf with set_real_ip_from … and real_ip_header CF-Connecting-IP;
2. Ensure DH param at /etc/nginx/ssl/dhparam.pem (default 4096 bits)
3. nginx -t validation, then exec NGINX

Environment knobs:
- CF_REFRESH=true|false (default true)
- CF_TIMEOUT=5 (curl timeout seconds)
- DHPARAM_BITS=4096

nginx.conf (defaults)
- Logging to stdout/stderr
- gzip + brotli (if module present)
- Cloudflare real IP: include /etc/nginx/cf/ips.conf
- resolver 1.1.1.1 1.0.0.1 8.8.8.8 valid=300s ipv6=off;
- TLS hardening (TLS 1.2/1.3, tickets off, session cache, custom ciphers, DH param)
- Security headers (global):
    - X-Content-Type-Options: nosniff
    - X-Frame-Options: DENY
    - Referrer-Policy: strict-origin-when-cross-origin
    - Permissions-Policy: camera=(), microphone=(), geolocation=()
    - Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
- WebSocket helper: map $http_upgrade $connection_upgrade { default upgrade; '' close; }
- Includes:
    - Internal: /etc/nginx/_internal/*.conf (healthz lives here)
    - Sites: /etc/nginx/conf.d/*.conf

## Quick start
docker-compose (recommended)
```yaml
version: "3.9"
services:
  nginx:
    image: prplanit/nginx-extras-oci:latest
    container_name: nginx-extras
    restart: always
    ports:
      - "80:80"
      - "443:443"
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /var/cache/nginx:rw,noexec,nosuid,nodev,size=64m
    environment:
      TZ: "America/Los_Angeles"
    dns: ["10.0.0.1","10.0.0.2"]
    dns_search: ["prplanit.internal"]
    volumes:
      # main config + sites
      - /opt/docker/nginx-extras/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/nginx/conf.d:/etc/nginx/conf.d:ro         # mount your vhosts here
      - /opt/docker/nginx-extras/snippets:/etc/nginx/snippets:ro
      # TLS & logs
      - /opt/docker/nginx-extras/ssl:/etc/nginx/ssl
      - /opt/docker/nginx-extras/logs:/var/log/nginx
      - /opt/docker/nginx-extras/letsencrypt:/etc/letsencrypt
      # share pid if you’ll SIGHUP from certbot
      - /var/run/nginx:/var/run/nginx
      # extras you rely on
      - /etc/nginx/dhparam.pem:/etc/nginx/dhparam.pem
      - /etc/nginx/cloudflare:/etc/nginx/cloudflare
      - /mnt/timecapsule/Server/Web-App/NGINX:/mnt/timecapsule/Server/Web-App/NGINX
    healthcheck:
      test: ["CMD-SHELL","wget -qO- http://127.0.0.1:8080/healthz >/dev/null"]
      interval: 30s
      timeout: 5s
      retries: 3

  certbot:
    image: certbot/dns-cloudflare:latest
    container_name: certbot
    restart: always
    pid: "service:nginx"  # lets deploy-hook HUP PID 1 (nginx) cleanly
    volumes:
      - /opt/docker/nginx-extras/letsencrypt:/etc/letsencrypt
      - /opt/docker/nginx-extras/secrets/dns_cloudflare_api_token.ini:/secrets/dns_cloudflare_api_token.ini:ro
    entrypoint:
      - sh
      - -c
      - |
        while :; do
          certbot renew \
            --dns-cloudflare \
            --dns-cloudflare-credentials /secrets/dns_cloudflare_api_token.ini \
            --preferred-challenges dns \
            --non-interactive --agree-tos \
            --deploy-hook 'kill -HUP 1' ;
          sleep 12h
        done
```
> Tip: uncomment user: "101:101", read_only: true, and capability lines if/when you want to harden further.

## docker run (minimal)
```bash
docker run -d --name nginx-extras \
  -p 80:80 -p 443:443 \
  -v /etc/nginx/conf.d:/etc/nginx/conf.d:ro \
  -v /opt/docker/nginx-extras/ssl:/etc/nginx/ssl \
  -v /opt/docker/nginx-extras/letsencrypt:/etc/letsencrypt \
  prplanit/nginx-extras-oci:latest
```
## Add a site (examples)
1) Simple reverse proxy (HTTP upstream, WebSockets ok)

Create /etc/nginx/conf.d/app.example.conf:
```nginx
server {
  listen 80;
  server_name app.example.com;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  server_name app.example.com;

  ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

  # proxy defaults (global map $connection_upgrade exists)
  proxy_http_version 1.1;
  proxy_buffering off;
  proxy_read_timeout 300s;
  proxy_set_header Host              $host;
  proxy_set_header X-Real-IP         $remote_addr;
  proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header Upgrade           $http_upgrade;
  proxy_set_header Connection        $connection_upgrade;

  location / {
    proxy_pass http://backend.internal:8080;
  }
}
```
2) Allow embedding (override global X-Frame-Options: DENY)
This image sets X-Frame-Options=DENY globally. To allow specific origins, clear XFO and use CSP:
```nginx
server {
  listen 443 ssl;
  server_name embed.example.com;

  ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

  # require headers-more (already installed)
  more_clear_headers X-Frame-Options;
  add_header Content-Security-Policy "frame-ancestors 'self' https://apps.example.com" always;

  location / { proxy_pass http://embed.internal:3000; }
}
```
## Certbot notes (DNS-01 via Cloudflare)
- Volumes persist the entire /etc/letsencrypt tree.
- pid: "service:nginx" plus --deploy-hook 'kill -HUP 1' reloads NGINX cleanly on renewal.
- Alternative: mount /var/run/nginx and nginx -s reload instead.

## Health, logs & introspection
```bash
# health
curl -fsS http://127.0.0.1:8080/healthz

# config dump / syntax check
docker exec -it nginx-extras nginx -T
docker exec -it nginx-extras nginx -t

# live logs
docker logs -f nginx-extras
```

## Troubleshooting (greatest hits)
- Container exits immediately → check docker logs; most often an invalid vhost in /etc/nginx/conf.d.
- 525 at Cloudflare → your origin must present a cert valid for the hostname CF is connecting to. Ensure:
    - The vhost server_name matches the SNI (Host) Cloudflare uses
    - No other earlier listen 443 ssl default_server; is catching the handshake
    - Cloudflare “SSL/TLS mode” is Full (Strict) if you require CA-signed validation
- Wrong cert shows up → another vhost is winning the match (default_server). Make sure your intended host either:
    - Uses an exact server_name and there’s no wildcard/_ default before it, or
    - Is marked as the only default_server.
- X-Frame-Options still DENY → you must more_clear_headers X-Frame-Options; in the same server block and rely on CSP frame-ancestors.
- HTTP/2 warning → on newer NGINX, listen 443 ssl http2 is deprecated; prefer:
```nginx
listen 443 ssl;
http2 on;
```
- Behind Cloudflare (real IP) → the entrypoint populates /etc/nginx/cf/ips.conf. Confirm it’s included and contains set_real_ip_from lines.

## Security hardening (optional)
- Run as non-root user: user: "101:101" in Compose
- Drop capabilities: cap_drop: ["ALL"]; cap_add: ["NET_BIND_SERVICE"]
- Make filesystem read-only: read_only: true + tmpfs for /var/cache/nginx (and /var/run/nginx if you enable it)
- Keep HSTS enabled (default)

##License
- This container is distributed under GPL-3.0 (see image labels).