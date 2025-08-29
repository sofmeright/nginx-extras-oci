# syntax=docker/dockerfile:1.7
FROM alpine:3.22.1

LABEL maintainer="SoFMeRight <sofmeright@gmail.com>" \
      org.opencontainers.image.title="nginx-extras-oci" \
      description="NGINX with extras, alpine base, with a default nginx.conf & healthcheck endpoint." \
      org.opencontainers.image.description="NGINX with extras, alpine base, with a default nginx.conf & healthcheck endpoint." \
      org.opencontainers.image.source="https://gitlab.prplanit.com/precisionplanit/nginx-extras-oci.git" \
      org.opencontainers.image.licenses="GPL-3.0"

# Core + dynamic modules we want available
RUN apk add --no-cache \
      nginx ca-certificates curl tzdata openssl \
      nginx-mod-http-brotli \
      nginx-mod-http-echo \
      nginx-mod-http-geoip2 \
      nginx-mod-http-headers-more

# Directories we use at runtime
RUN mkdir -p /etc/nginx/modules.d /etc/nginx/_internal /etc/nginx/cf /etc/nginx/ssl

# Load dynamic modules at startup (keep one file per module for clarity)
RUN printf 'load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;\n' \
      > /etc/nginx/modules.d/10-headers_more.conf \
 && printf 'load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;\nload_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;\n' \
      > /etc/nginx/modules.d/20-brotli.conf

# Bake a private health endpoint (not in conf.d, not exposed publicly)
RUN printf 'server {\n  listen 127.0.0.1:8080;\n  server_name _;\n  access_log off;\n  location = /healthz { add_header Content-Type text/plain; return 200 \"ok\"; }\n}\n' \
      > /etc/nginx/_internal/10-healthz.conf

# Bake our nginx.conf (ships with sane defaults; site vhosts live in /etc/nginx/conf.d)
COPY nginx.conf /etc/nginx/nginx.conf

# Entrypoint:
#  - refresh Cloudflare real-IP ranges into /etc/nginx/cf/ips.conf
#  - ensure /etc/nginx/ssl/dhparam.pem exists (4096-bit by default)
#  - test config, then exec nginx in foreground
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports; stop politely
EXPOSE 80 443
STOPSIGNAL SIGQUIT

# Inline healthcheck (allowing extra startup time for DH param/gen etc.)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=120s \
  CMD sh -c 'curl -fsS http://127.0.0.1:8080/healthz >/dev/null || exit 1'

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]