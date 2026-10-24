# Included by every location of default.conf (nginx.conf). pages_headers is
# the Cloudflare Pages copy (web.vommet.app): keep the two in step.
# 40-vommet-config.sh drops the two Cross-Origin lines when
# VOMMET_CROSS_ORIGIN_ISOLATION=off.
add_header X-Content-Type-Options nosniff always;
add_header Referrer-Policy no-referrer always;
add_header X-Frame-Options DENY always;
add_header Cross-Origin-Opener-Policy same-origin always;
add_header Cross-Origin-Embedder-Policy credentialless always;
