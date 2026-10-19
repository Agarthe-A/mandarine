"""Petit serveur statique avec requêtes Range (Safari/iPhone en a besoin pour lire une vidéo).
Usage: python3 serve.py <dossier> <adresse> <port>"""
import os, re, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class H(SimpleHTTPRequestHandler):
    def send_head(self):
        rng = self.headers.get("Range")
        path = self.translate_path(self.path)
        if not rng or not os.path.isfile(path):
            return super().send_head()
        m = re.match(r"bytes=(\d*)-(\d*)$", rng.strip())
        size = os.path.getsize(path)
        if not m or (not m.group(1) and not m.group(2)):
            return super().send_head()
        if m.group(1):
            a = int(m.group(1)); b = int(m.group(2)) if m.group(2) else size - 1
        else:
            a = max(0, size - int(m.group(2))); b = size - 1
        b = min(b, size - 1)
        if a > b:
            self.send_error(416); return None
        f = open(path, "rb"); f.seek(a)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {a}-{b}/{size}")
        self.send_header("Content-Length", str(b - a + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self._left = b - a + 1
        return f

    def copyfile(self, src, dst):
        left = getattr(self, "_left", None)
        if left is None:
            return super().copyfile(src, dst)
        while left > 0:
            chunk = src.read(min(65536, left))
            if not chunk: break
            dst.write(chunk); left -= len(chunk)
        self._left = None

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

if __name__ == "__main__":
    os.chdir(sys.argv[1])
    ThreadingHTTPServer((sys.argv[2], int(sys.argv[3])), H).serve_forever()
