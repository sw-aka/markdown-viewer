#!/usr/bin/env python3
"""Local signed-update integration fixture. The app accepts it in Debug only."""
import argparse
import json
import pathlib
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=pathlib.Path, required=True)
parser.add_argument('--port', type=int, default=8767)
args = parser.parse_args()
root = args.root.resolve()
base = f'http://127.0.0.1:{args.port}'
repo = 'sw-aka/markdown-viewer'
archive = 'MarkdownViewer-0.1.500-development.zip'
requests = []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        scenario = (root / 'scenario.txt').read_text().strip() if (root / 'scenario.txt').exists() else 'available'
        requests.append(dict(path=self.path, time=time.time()))
        (root / 'requests.json').write_text(json.dumps(requests))
        if self.path == '/status':
            return self.send(json.dumps(requests).encode(), 'application/json')
        if scenario == 'error' and '/repos/' in self.path:
            return self.send(b'{}', 'application/json', 503)
        assets = [dict(name=name, browser_download_url=f'{base}/{repo}/releases/download/dev-0.1.500/{name}') for name in ['appcast.xml', archive]]
        release = dict(tag_name='dev-0.1.500', name='Development 0.1.500', body='Signed integration update. Your current work is preserved.', draft=False, prerelease=True, assets=assets)
        if self.path.startswith(f'/repos/{repo}/releases/latest'):
            return self.send(b'{}', 'application/json', 404)
        if self.path.startswith(f'/repos/{repo}/releases?'):
            return self.send(json.dumps([] if scenario == 'no-updates' else [release]).encode(), 'application/json')
        if self.path.endswith('/appcast.xml'):
            xml = ET.parse(root / 'appcast.xml')
            enclosure = xml.find('channel/item/enclosure')
            enclosure.set('url', assets[1]['browser_download_url'])
            if scenario == 'bad-signature':
                enclosure.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature', 'A' * 86 + '==')
            return self.send(ET.tostring(xml.getroot()), 'application/xml')
        if self.path.endswith('/' + archive):
            path = root / archive
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(path.stat().st_size))
            self.end_headers()
            try:
                with path.open('rb') as stream:
                    while chunk := stream.read(65536):
                        self.wfile.write(chunk)
                        self.wfile.flush()
                        time.sleep(0.25)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self.send(b'not found', 'text/plain', 404)

    def send(self, data, content_type, status=200):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
