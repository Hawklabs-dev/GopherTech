import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools import setup_browser


class BrowserSetupTests(unittest.TestCase):
    def test_checksum_failure_writes_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'bad.zip'
            archive.write_bytes(b'invalid archive')
            root = Path(folder) / 'project'
            with patch.object(setup_browser, 'ROOT', root):
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    setup_browser.install(archive)
            self.assertFalse(root.exists())

    def test_release_prefix_platform_selection_and_helper_permission(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'fixture.zip'
            prefix = 'dist/addons/godot_cef/'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr(prefix + 'godot_cef.gdextension', 'fixture')
                bundle.writestr(prefix + 'bin/x86_64-unknown-linux-gnu/gdcef_helper', 'fixture')
                bundle.writestr(prefix + 'bin/x86_64-pc-windows-msvc/gdcef.dll', 'fixture')
            root = Path(folder) / 'project'
            with patch.object(setup_browser, 'ROOT', root), patch.object(setup_browser, 'SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()), patch('platform.system', return_value='Linux'), patch('platform.machine', return_value='x86_64'):
                setup_browser.install(archive)
            addon = root / 'addons/godot_cef'
            self.assertTrue((addon / 'godot_cef.gdextension').is_file())
            self.assertTrue((addon / 'bin/.gdignore').is_file())
            self.assertTrue((addon / 'bin/x86_64-unknown-linux-gnu/gdcef_helper').stat().st_mode & 0o100)
            self.assertFalse((addon / 'bin/x86_64-pc-windows-msvc').exists())
