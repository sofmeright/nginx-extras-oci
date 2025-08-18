# Dockerfile
FROM 3.13.7-alpine3.22

# Core + “extras”-style modules you likely want
RUN apk add --no-cache \
      nginx ca-certificates curl tzdata \
      nginx-mod-http-headers-more \
      nginx-mod-http-brotli \
      nginx-mod-http-geoip2 \
      nginx-mod-http-echo

# Make Alpine’s default include dir (“http.d”) compatible with your existing conf.d
# (Alpine’s nginx.conf includes /etc/nginx/http.d/*.conf by default)
RUN ln -s /etc/nginx/http.d /etc/nginx/conf.d

# Enable dynamic modules (Alpine puts them in /usr/lib/nginx/modules)
# Add one file per module to keep things tidy
RUN mkdir -p /etc/nginx/modules.d && \
    printf "load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;\n" > /etc/nginx/modules.d/headers_more.conf && \
    printf "load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;\nload_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;\n" > /etc/nginx/modules.d/brotli.conf

# Optional: keep Cloudflare IPs fresh on container start
# (real IPs for logging/rate limiting)
RUN mkdir -p /docker-entrypoint.d /etc/nginx/cf
ADD https://www.cloudflare.com/ips-v4 /etc/nginx/cf/ips-v4
ADD https://www.cloudflare.com/ips-v6 /etc/nginx/cf/ips-v6
RUN printf '#!/bin/sh\n'\
'set -e\n'\
'CF=/etc/nginx/cf/ips.conf\n'\
'curl -fsS https://www.cloudflare.com/ips-v4 > /etc/nginx/cf/ips-v4 || true\n'\
'curl -fsS https://www.cloudflare.com/ips-v6 > /etc/nginx/cf/ips-v6 || true\n'\
'{\n'\
'  echo "# generated";\n'\
'  while read n; do echo "set_real_ip_from $n;"; done < /etc/nginx/cf/ips-v4;\n'\
'  while read n; do echo "set_real_ip_from $n;"; done < /etc/nginx/cf/ips-v6;\n'\
'  echo "real_ip_header CF-Connecting-IP;";\n'\
'} > "$CF"\n'\
'> /dev/null\n'\
>> /docker-entrypoint.d/30-cloudflare-realip.sh && chmod +x /docker-entrypoint.d/30-cloudflare-realip.sh

EXPOSE 80 443
STOPSIGNAL SIGQUIT
CMD ["sh", "-c", "nginx -g 'daemon off;'"]