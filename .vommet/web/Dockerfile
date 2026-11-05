# Vommet web: the Flutter web build (commet/build/web, built by
# .github/workflows/vommet-web.yml) served by unprivileged nginx on :8080.
# Runtime config: see 40-vommet-config.sh.
FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY .vommet/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=101:101 .vommet/web/headers.inc /etc/nginx/conf.d/vommet-headers.inc
COPY --chmod=755 .vommet/web/40-vommet-config.sh /docker-entrypoint.d/40-vommet-config.sh
COPY --chown=101:101 commet/build/web /usr/share/nginx/html
# Pre-compressed copies for gzip_static (not the runtime config, which the
# entrypoint may rewrite); source maps stay out of the image. woff2 is
# compressed already.
USER root
RUN find /usr/share/nginx/html -name '*.map' -delete \
 && find /usr/share/nginx/html -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' -o -name '*.json' -o -name '*.css' -o -name '*.svg' -o -name '*.ttf' -o -name '*.otf' \) \
      ! -path '*/assets/config/*' -exec gzip -9 -k {} + \
 && chown -R 101:101 /usr/share/nginx/html
USER 101
EXPOSE 8080
