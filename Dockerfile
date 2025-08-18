# Dockerfile
FROM alpine:3.22.1

# nginx + useful dynamic modules + openssl for dhparam
RUN apk add --no-cache \
      nginx ca-certificates curl tzdata openssl \
      nginx-mod-http-headers-more \
      nginx-mod-http-brotli \
      nginx-mod-http-geoip2 \
      nginx-mod-http-echo

# Alpine includes /etc/nginx/http.d; symlink your conf.d into it
RUN ln -s /etc/nginx/http.d /etc/nginx/conf.d

# Enable dynamic modules (load at runtime)
RUN mkdir -p /etc/nginx/modules.d && \
    printf "load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;\n" > /etc/nginx/modules.d/headers_more.conf && \
    printf "load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;\nload_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;\n" > /etc/nginx/modules.d/brotli.conf

# CF real IPs live here; dhparam & other TLS bits in /etc/nginx/ssl
RUN mkdir -p /etc/nginx/cf /etc/nginx/ssl

# One entrypoint that:
#  - refreshes Cloudflare IP ranges (real client IPs)
#  - ensures /etc/nginx/ssl/dhparam.pem exists, 4096-bit (generates if missing)
#  - starts nginx in foreground
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]