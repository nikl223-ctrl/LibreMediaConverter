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
        page.wait_for_function('window.__TRUCK_POC && window.__TRUCK_POC.running',timeout=30000)
        page.wait_for_timeout(1500)
        state=page.evaluate('({renderer:window.__TRUCK_POC.renderer, loaded:window.__TRUCK_POC.loaded, running:window.__TRUCK_POC.running, dist:window.__TRUCK_POC.distance, serverFrames:window.__TRUCK_POC.serverFrames})')
        assert state['renderer'] in ('WebGL2','WebGPU','Canvas2D (CPU-Fallback)'),state
        assert state['loaded'] and state['running'],state
        assert state['dist']>0,state
        assert state['serverFrames']==0,state
        assert not errors,errors
        screenshot=ROOT/'browser-smoke.png'
        page.screenshot(path=str(screenshot))
        print('BROWSER_GPU_PROOF',state,'screenshot:',screenshot)
        browser.close()
finally:
    proc.terminate()
    try:proc.wait(timeout=3)
    except subprocess.TimeoutExpired:proc.kill()
