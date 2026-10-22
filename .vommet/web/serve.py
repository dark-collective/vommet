#!/usr/bin/env python3
# Vommet web smoke test server: static files with the headers the web image
# sends (COOP same-origin + COEP credentialless = cross-origin isolated, which
# the multi-threaded skwasm renderer needs) and the wasm MIME type.
#   serve.py <dir> <port>
import functools, http.server, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".mjs": "text/javascript",
                      ".js": "text/javascript", ".woff2": "font/woff2"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        super().end_headers()

    def log_message(self, *args):
        pass

d, port = sys.argv[1], int(sys.argv[2])
http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=d)).serve_forever()
