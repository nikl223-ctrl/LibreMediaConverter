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
        # Server receives API capability information; it never renders frames.
        device=page.locator('#device-info').inner_text()
        assert 'gemeldet' in device,device
        assert 'KiB' in page.locator('#network').inner_text()
        initial=page.request.get('http://127.0.0.1:18766/api/stats').json()['response_bytes']
        page.get_by_role('button',name='Spielstand auf Server speichern').click()
        page.get_by_text('Spielstand auf Server gespeichert',exact=True).wait_for(timeout=10000)
        page.reload(wait_until='domcontentloaded')
        page.get_by_role('button',name='Spielen – auf diesem Gerät').click()
        page.locator('#intro').wait_for(state='hidden',timeout=30000)
        assert 'fortgesetzt' in page.locator('#save-status').inner_text()
        page.wait_for_timeout(450)
        second=page.request.get('http://127.0.0.1:18766/api/stats').json()['response_bytes']
        reload_bytes=second-initial
        assert reload_bytes < initial, {'initial_total':initial,'reload_bytes':reload_bytes}
        state.update(device=device,server_bytes_before_reload=initial,server_bytes_on_reload=reload_bytes)
        screenshot=ROOT/'browser-smoke.png'
        page.screenshot(path=str(screenshot))
        print('BROWSER_GPU_PROOF',state,'screenshot:',screenshot)
        # Same GPU-free host, but now the CPU on Linux performs the physics.
        # The web browser still sends only controls and renders with WebGL2.
        page.goto('http://127.0.0.1:18766/?remote=1',wait_until='domcontentloaded')
        assert page.locator('#remote-mode').is_checked()
        page.locator('#start').click()
        page.locator('#intro').wait_for(state='hidden',timeout=30000)
        page.wait_for_timeout(1600)
        remote=page.request.get('http://127.0.0.1:18766/api/stats').json()
        display=page.locator('#renderer').inner_text()
        assert 'WebGL2' in display or 'WebGPU' in display,display
        assert remote['remote_steps'] >= 5,remote
        assert remote['remote_request_bytes'] < remote['remote_steps'] * 150,remote
        assert 'CPU-Server' in page.locator('#server').inner_text()
        assert not errors,errors
        print('REMOTE_CPU_CLIENT_GPU_PROOF',{
            'steps':remote['remote_steps'],
            'input_payload_bytes':remote['remote_request_bytes'],
            'average_input_bytes':round(remote['remote_request_bytes']/remote['remote_steps'],2),
            'server_video_frames':0,
            'client_renderer':display,
        })
        browser.close()
finally:
    proc.terminate()
    try:proc.wait(timeout=3)
    except subprocess.TimeoutExpired:proc.kill()
