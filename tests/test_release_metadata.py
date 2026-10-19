import importlib.util
import pathlib
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('release', pathlib.Path(__file__).resolve().parents[1] / 'scripts/release-metadata.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_channels_and_asset_addresses(self):
        dev = release.metadata('0.1', 42, 'development', 'example/app')
        stable = release.metadata('0.1', 43, 'stable', 'example/app')
        self.assertEqual(dev['tag'], 'dev-0.1.42')
        self.assertEqual(stable['tag'], 'v0.1.43')
        self.assertIn('/releases/download/dev-0.1.42/', dev['download'])

    def test_feed_contains_verified_download_and_version(self):
        meta = release.metadata('0.1', 42, 'development', 'example/app')
        xml = ET.fromstring(release.appcast(meta, 'A' * 86 + '==', 1234))
        item = xml.find('channel/item')
        self.assertEqual(item.find(f'{{{release.SPARKLE}}}version').text, '0.1.42')
        self.assertEqual(item.find('enclosure').attrib['url'], meta['download'])
        self.assertEqual(item.find('enclosure').attrib['length'], '1234')

    def test_reject_bad_inputs(self):
        for number in [0, 10000]:
            with self.assertRaises(ValueError):
                release.metadata('0.1', number, 'stable', 'example/app')
        with self.assertRaises(ValueError):
            release.metadata('not-a-version', 1, 'stable', 'example/app')
        with self.assertRaises(ValueError):
            release.appcast(release.metadata('0.1', 1, 'stable', 'example/app'), 'invalid', 12)


if __name__ == '__main__':
    unittest.main()
