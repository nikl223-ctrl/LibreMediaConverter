import json
import os
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE='http://127.0.0.1:18765'

class AssetServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc=subprocess.Popen([sys.executable,str(ROOT/'server.py')],env={**os.environ,'PORT':'18765','HOST':'127.0.0.1','QUIET':'1'},stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        for _ in range(60):
            try:
                with urllib.request.urlopen(BASE+'/health',timeout=.2) as r:
                    if r.status==200:return
            except (OSError,urllib.error.URLError):
                time.sleep(.1)
        raise RuntimeError('test HTTP server did not start')

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate()
        try:cls.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:cls.proc.kill()

    def get(self,path,headers=None):
        req=urllib.request.Request(BASE+path,headers=headers or {})
        with urllib.request.urlopen(req,timeout=5) as response:return response.status,response.headers,response.read()

    def test_cpu_server(self):
        status,_,raw=self.get('/api/capabilities')
        data=json.loads(raw)
        self.assertEqual(status,200)
        self.assertFalse(data['server_gpu'])
        self.assertFalse(data['native_windows_exe_in_browser'])

    def test_game_level_downloaded_on_demand(self):
        status,h,raw=self.get('/api/world')
        data=json.loads(raw)
        self.assertEqual(status,200)
        self.assertEqual(h['X-Asset-Source'],'local')
        self.assertGreater(data['track']['length'],1500)
        self.assertIn('vehicle',data)

    def test_http_byte_range(self):
        _,_,full=self.get('/assets/world.json')
        status,headers,piece=self.get('/assets/world.json',{'Range':'bytes=0-31'})
        self.assertEqual(status,206)
        self.assertEqual(piece,full[:32])
        self.assertEqual(headers['Content-Range'],f'bytes 0-31/{len(full)}')

    def test_no_directory_or_secret_access(self):
        for path in ['/server.py','/.env','/../server.py','/assets/../../server.py']:
            with self.subTest(path=path):
                with self.assertRaises(urllib.error.HTTPError) as ctx:
                    self.get(path)
                self.assertEqual(ctx.exception.code,404)

    def test_html_assets(self):
        status,_,raw=self.get('/')
        self.assertEqual(status,200)
        self.assertIn(b'/game.js',raw)
        status,_,raw=self.get('/game.js')
        self.assertEqual(status,200)
        self.assertIn(b'WebGPU',raw)
        self.assertIn(b'WebGL2',raw)

if __name__=='__main__':unittest.main()
