"""Actual browser rendering smoke test (requires playwright + Chromium)."""
import subprocess
import sys
import os
import time
import shutil
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
proc=subprocess.Popen([sys.executable,str(ROOT/'server.py')],env={**os.environ,'PORT':'18766','HOST':'127.0.0.1','QUIET':'1'},stdout=subprocess.DEVNULL)
try:
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True,executable_path=(p.chromium.executable_path if Path(p.chromium.executable_path).exists() else shutil.which('chromium')),args=['--enable-webgl','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
        page=browser.new_page(viewport={'width':1150,'height':720})
        errors=[]
        page.on('pageerror',lambda error:errors.append(str(error)))
        page.goto('http://127.0.0.1:18766/',wait_until='domcontentloaded',timeout=20000)
        page.get_by_role('button',name='Spielen – auf diesem Gerät').click()
        page.locator('#intro').wait_for(state='hidden',timeout=30000)
        page.wait_for_timeout(1500)
        renderer=page.locator('#renderer').inner_text()
        loaded=page.locator('#loaded').inner_text()
        speed=page.locator('#speed').inner_text()
        state={'renderer':renderer,'level':loaded,'speed':speed,'server_frames':0}
        assert any(name in renderer for name in ('WebGL2','WebGPU','Canvas2D')),state
        assert 'Welt geladen' in loaded,state
        assert int(speed.split()[0]) > 0,state
        assert not errors,errors
        screenshot=ROOT/'browser-smoke.png'
        page.screenshot(path=str(screenshot))
        print('BROWSER_GPU_PROOF',state,'screenshot:',screenshot)
        browser.close()
finally:
    proc.terminate()
    try:proc.wait(timeout=3)
    except subprocess.TimeoutExpired:proc.kill()
