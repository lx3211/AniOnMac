"""Run with python3 -m unittest discover -s development/tests -p 'test_*.py'.
Uses only the Python standard library; never registers a system cursor.
"""
import binascii
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'AniOnMac.app/Contents/Resources/anicore'
CTL = ROOT / 'AniOnMac.app/Contents/Resources/cursorctl'


def png_chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)


def cur(hot):
    pixels = b''.join(b'\0' + b''.join(bytes((255, 0, 0, 255)) if (x, y) == hot else bytes(4) for x in range(4)) for y in range(4))
    image = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>2I5B', 4, 4, 8, 6, 0, 0, 0)) + png_chunk(b'IDAT', zlib.compress(pixels)) + png_chunk(b'IEND', b'')
    return struct.pack('<3H', 0, 2, 1) + struct.pack('<4B2H2I', 4, 4, 0, 0, *hot, len(image), 22) + image


def chunk(tag, data):
    return tag + struct.pack('<I', len(data)) + data + b'\0' * (len(data) % 2)


def ani():
    data = b'ACON' + chunk(b'anih', struct.pack('<9I', 36, 2, 3, 4, 4, 32, 1, 6, 3))
    data += chunk(b'seq ', struct.pack('<3I', 1, 0, 1)) + chunk(b'rate', struct.pack('<3I', 6, 12, 6))
    data += chunk(b'LIST', b'fram' + chunk(b'icon', cur((1, 2))) + chunk(b'icon', cur((2, 1))))
    return b'RIFF' + struct.pack('<I', len(data)) + data


class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'development/.build')
        self.path = Path(self.temp.name)
        self.source = self.path / 'sample.ani'
        self.source.write_bytes(ani())

    def tearDown(self):
        self.temp.cleanup()

    def run_core(self, *args, ok=True):
        result = subprocess.run([str(CORE), *map(str, args)], text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return json.loads(result.stdout) if ok else result

    def test_sequence_rate_alignment(self):
        meta = self.run_core('preview', self.source, self.path / 'preview')
        self.assertEqual(meta['aligned_canvas_px'], [5, 5])
        self.assertEqual(meta['playback_frames'], [1, 0, 0, 1])
        self.assertAlmostEqual(meta['frame_duration_seconds'], .1)
        self.assertEqual(meta['hotspot_points'], [51.2, 51.2])

    def test_partial_theme_custom_hotspot(self):
        config = self.path / 'config.json'
        config.write_text(json.dumps(dict(name='Test', slots=[dict(role='arrow', path=str(self.source), size=64, hotspot=[.25, .75])])))
        result = self.run_core('export', config, self.path / 'export')
        data = plistlib.loads(Path(result['cape']).read_bytes())['Cursors']
        self.assertEqual(list(data), ['com.apple.coregraphics.Arrow'])
        self.assertEqual(data['com.apple.coregraphics.Arrow']['HotSpotX'], 16)
        self.assertEqual(data['com.apple.coregraphics.Arrow']['HotSpotY'], 48)
        subprocess.run([CTL, 'validate', result['cape']], check=True, capture_output=True)

    def test_white_outline_padding_at_both_densities(self):
        config = self.path / 'config.json'
        roles = [('arrow', 'com.apple.coregraphics.Arrow', 32), ('pointing', 'com.apple.cursor.13', 64),
                 ('text', 'com.apple.coregraphics.IBeam', 24), ('wait', 'com.apple.coregraphics.Wait', 40)]
        slots = [dict(role=role, path=str(self.source), size=size, hotspot=[.25, .75])
                 for role, _, size in roles]
        results = []
        for enabled in (False, True):
            options = dict(slots=slots, whiteOutline=True) if enabled else dict(slots=slots)
            config.write_text(json.dumps(options))
            result = self.run_core('export', config, self.path / str(enabled))
            subprocess.run([CTL, 'validate', result['cape']], check=True, capture_output=True)
            results.append(plistlib.loads(Path(result['cape']).read_bytes())['Cursors'])

        for _, key, size in roles:
            original, outlined = (result[key] for result in results)
            points = size + 2
            self.assertEqual([original['PointsWide'], original['PointsHigh']], [size, size])
            self.assertEqual([outlined['PointsWide'], outlined['PointsHigh']], [points, points])
            self.assertEqual([outlined['HotSpotX'], outlined['HotSpotY']], [size * .25 + 1, size * .75 + 1])
            for field in ('FrameCount', 'FrameDuration'):
                self.assertEqual(outlined[field], original[field])
            for density, image in enumerate(outlined['Representations'], 1):
                self.assertEqual(struct.unpack('>2I', image[16:24]), (points * density, points * density * outlined['FrameCount']))

    def test_25_step_boundary(self):
        for steps in (25, 26):
            data = b'ACON' + chunk(b'anih', struct.pack('<9I', 36, 2, steps, 4, 4, 32, 1, 18, 3))
            sequence = [i % 2 for i in range(steps)]
            data += chunk(b'seq ', struct.pack('<' + 'I' * steps, *sequence))
            data += chunk(b'LIST', b'fram' + chunk(b'icon', cur((1, 2))) + chunk(b'icon', cur((2, 1))))
            self.source.write_bytes(b'RIFF' + struct.pack('<I', len(data)) + data)
            output = self.path / str(steps)
            if steps == 26:
                self.run_core('preview', self.source, output, ok=False)
                continue
            meta = self.run_core('preview', self.source, output)
            self.assertEqual(meta['source_steps'], 25)
            self.assertEqual(meta['playback_frames'], sequence[:24])
            self.assertAlmostEqual(meta['frame_duration_seconds'], 0.3125)
            self.assertAlmostEqual(meta['frame_duration_seconds'] * 24, 7.5)
            config = self.path / 'config.json'
            config.write_text(json.dumps(dict(slots=[dict(role='pointing', path=str(self.source), size=32)])))
            result = self.run_core('export', config, self.path / 'export')
            subprocess.run([CTL, 'validate', result['cape']], check=True, capture_output=True)

    def test_invalid_or_empty_theme(self):
        self.source.write_bytes(ani()[:-1])
        self.run_core('preview', self.source, self.path / 'invalid', ok=False)
        self.assertFalse((self.path / 'invalid').exists())
        config = self.path / 'empty.json'
        config.write_text('{"slots":[]}')
        self.run_core('export', config, self.path / 'empty', ok=False)

    def test_out_of_bounds_hotspot(self):
        config = self.path / 'bad.json'
        config.write_text(json.dumps(dict(slots=[dict(role='arrow', path=str(self.source), size=32, hotspot=[1, 0])])))
        self.run_core('export', config, self.path / 'bad', ok=False)

    def test_translation_parity_and_no_chinese_full_stops(self):
        resources = ROOT / 'development/resources'
        zh = json.loads((resources / 'zh-Hant.json').read_text())
        en = json.loads((resources / 'en.json').read_text())
        self.assertEqual(set(zh), set(en))
        self.assertTrue(all('。' not in value for value in zh.values()))

    def test_native_defaults_are_not_custom_backup(self):
        output = self.path / 'native.cape'
        subprocess.run([CTL, 'defaults-export', output], check=True, capture_output=True)
        cursors = plistlib.loads(output.read_bytes())['Cursors']
        self.assertEqual(len(cursors), 4)
        wait = cursors['com.apple.coregraphics.Wait']
        self.assertEqual(wait['NativeSourceFrames'], 30)
        self.assertEqual(wait['FrameCount'], 15)  # macOS 26.6.2 local resource fixture
        self.assertAlmostEqual(wait['FrameDuration'] * wait['FrameCount'], 0.5, places=6)


if __name__ == '__main__':
    unittest.main()
