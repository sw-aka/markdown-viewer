#!/usr/bin/env python3
"""Publish only fully built and signed release assets from GitHub Actions."""
import json
import os
import pathlib
import subprocess

root = pathlib.Path('build/release')
meta = json.loads((root / 'release.json').read_text())
if os.environ.get('GITHUB_ACTIONS') != 'true':
    raise SystemExit('Publication is restricted to the reviewed GitHub Actions workflow.')
for asset in [root / meta['archive'], root / 'appcast.xml']:
    if not asset.is_file():
        raise SystemExit(f'Missing signed release asset: {asset}')
args = ['gh', 'release', 'create', meta['tag'], str(root / meta['archive']), str(root / 'appcast.xml'),
        '--repo', meta['repository'], '--target', os.environ['GITHUB_SHA'],
        '--title', f'{meta["channel"].title()} {meta["version"]}', '--generate-notes']
args += ['--prerelease', '--latest=false'] if meta['channel'] == 'development' else ['--latest']
# Never overwrite an existing release or mutate an old signed download.
subprocess.run(args, check=True)
