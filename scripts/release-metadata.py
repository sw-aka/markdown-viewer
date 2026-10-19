#!/usr/bin/env python3
"""Deterministic release names and signed Sparkle feed generation."""
import argparse
import json
import pathlib
import re
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def metadata(series, number, channel, repository):
    if not re.fullmatch(r'\d{1,4}\.\d{1,2}', series):
        raise ValueError('RELEASE_SERIES must contain major.minor numeric components.')
    if not 1 <= int(number) <= 9999:
        raise ValueError('Build number must be between 1 and 9999. Advance RELEASE_SERIES before resetting numbering.')
    if channel not in {'development', 'stable'}:
        raise ValueError('Unknown channel.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Expected owner/repository.')
    version = f'{series}.{int(number)}'
    tag = f'{"dev-" if channel == "development" else "v"}{version}'
    archive = f'MarkdownViewer-{version}-{channel}.zip'
    return dict(version=version, tag=tag, archive=archive, channel=channel, repository=repository,
                download=f'https://github.com/{repository}/releases/download/{tag}/{archive}')


def appcast(meta, signature, size):
    if not re.fullmatch(r'[A-Za-z0-9+/]{86}==', signature):
        raise ValueError('A valid Ed25519 signature is required.')
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Markdown Viewer'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'{meta["channel"].title()} {meta["version"]}'
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = meta['version']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = meta['version']
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '26.0'
    ET.SubElement(item, 'enclosure', url=meta['download'], length=str(size),
                  type='application/octet-stream', attrib={f'{{{SPARKLE}}}edSignature': signature})
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--series', required=True)
    parser.add_argument('--number', required=True, type=int)
    parser.add_argument('--channel', required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--signature-file', type=pathlib.Path)
    parser.add_argument('--archive', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    meta = metadata(args.series, args.number, args.channel, args.repository)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'release.json').write_text(json.dumps(meta, indent=2) + '\n')
    if args.signature_file and args.archive:
        (args.output / 'appcast.xml').write_bytes(appcast(meta, args.signature_file.read_text().strip(), args.archive.stat().st_size))
    print(json.dumps(meta))


if __name__ == '__main__':
    main()
