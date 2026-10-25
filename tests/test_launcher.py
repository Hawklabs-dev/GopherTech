import json
import os
from pathlib import Path
import tempfile
import unittest
import urllib.request
from unittest.mock import patch
import database
import main
import launch


class LauncherTests(unittest.TestCase):
    def test_owned_backend_health_and_shutdown(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(database,'DATABASE',Path(directory)/'test.db'), patch.object(main,'DATABASE',Path(directory)/'test.db'), patch.dict(os.environ,GOPHERTECH_LOCAL_AI='0'):
            urls=[]
            def frontend(args,env):
                urls.append(env['GOPHERTECH_API_URL'])
                with urllib.request.urlopen(urls[0]+'/system/info',timeout=3) as response:
                    info=json.load(response)
                self.assertEqual(info['backend_revision'],'shop-buddy-2-3')
                self.assertFalse(info['paid_calls'])
                return 0
            with patch('launch.subprocess.call',side_effect=frontend),patch('sys.argv',['launch.py']):
                self.assertEqual(launch.main(),0)
            with self.assertRaises(OSError):
                urllib.request.urlopen(urls[0]+'/health',timeout=1)
