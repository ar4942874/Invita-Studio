"""Serve the compiled Flutter web app on a preview-compatible origin."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8080);p.add_argument('--directory',default='build/web');args=p.parse_args()
root=Path(args.directory).resolve()
if not (root/'main.dart.js').exists():raise SystemExit('Build the app first: flutter build web --no-web-resources-cdn --no-wasm-dry-run -O1')
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**k):super().__init__(*a,directory=str(root),**k)
 def end_headers(self):
  self.send_header('Cache-Control','no-store')
  # No X-Frame-Options/host allowlist: safe to embed in the Arena preview.
  super().end_headers()
 def log_message(self,fmt,*a):
  if not str(a[1] if len(a)>1 else '').startswith('2'):super().log_message(fmt,*a)
print(f'Invita Studio at http://0.0.0.0:{args.port}',flush=True)
ThreadingHTTPServer(('0.0.0.0',args.port),Handler).serve_forever()
