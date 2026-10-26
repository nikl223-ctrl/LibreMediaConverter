#!/usr/bin/env python3
"""Create directly active Bedrock PBR resource pack, with detailed core albedo.

Resolves the previous optional-subpack issue by materializing the VH/vanilla-cloud
assets at the resource-pack root. Native photographic detail cannot be recovered
from 16px source; this adds deterministic, tileable fine-grain material structure
to the existing colors. Use modest sizes to reduce Xbox crash risk.
"""
import hashlib, io, json, math, pathlib, sys, uuid, zipfile
import numpy as np
from PIL import Image, ImageFilter

HERO = ('grass_', 'dirt', 'stone', 'cobblestone', 'moss', 'sand',
        'planks_', '_log', 'log_', 'wood', 'leaves', 'mud', 'snow', 'ice',
        'mushroom', 'netherrack', 'deepslate', 'gravel', 'clay',
        'brick', 'ore', 'terracotta', 'concrete', 'mycelium', 'podzol',
        'tuff', 'basalt', 'andesite', 'granite', 'diorite')
SKY = ('/textures/environment/overworld_cubemap/',)
def remove_cloud(n):
    x=n.lower()
    return (x=='textures/environment/clouds.png' or
            x.endswith('/textures/environment/clouds.png') or
            any(k in x for k in SKY) or x=='cubemaps/default_cubemap.json')
def material_kind(name):
    s=pathlib.PurePosixPath(name.lower()).stem
    if s.endswith('_heightmap'): return 'height'
    if s.endswith('_mers'): return 'mers'
    if s.endswith('_normal') and not ('sandstone_normal' in s or 'rail_normal' in s): return 'normal'
    return 'albedo'
def noise_tile(width,seed,grid):
    rng=np.random.default_rng(seed)
    small=rng.normal(0,1,size=(grid,grid)).astype('float32')
    tile=Image.fromarray(small,mode='F').resize((width,width),Image.Resampling.BICUBIC)
    arr=np.asarray(tile,dtype='float32')
    # Force edge wrap via periodic shift/averaging so tiles don't get bright seams.
    fade=np.linspace(0,1,width,dtype='float32')
    x=arr.copy()
    for i in range(width):
        t=min(i,width-1-i)
        if t < width//8:
            opposite=width-1-i
            weight=t/(width//8)
            x[:,i]=weight*arr[:,i]+(1-weight)*.5*(arr[:,i]+arr[:,opposite])
    arr=x.copy()
    for i in range(width):
        t=min(i,width-1-i)
        if t < width//8:
            opposite=width-1-i
            weight=t/(width//8)
            x[i,:]=weight*arr[i,:]+(1-weight)*.5*(arr[i,:]+arr[opposite,:])
    return x
def render(name,raw):
    if not name.lower().endswith(('.png','.tga')): return None
    kind=material_kind(name)
    stem=pathlib.PurePosixPath(name).stem.lower()
    hero=any(k in stem for k in HERO)
    if not hero: return None
    try:
        with Image.open(io.BytesIO(raw)) as img:
            img.load()
            w,h=img.size
            # Do not corrupt animation strips, transparent sprite layouts, atlas sheets.
            if w!=h or w not in (16,32,64): return None
            target=256 if kind=='albedo' else 128
            if w>=target: return None
            if img.mode=='P': img=img.convert('RGBA')
            if img.mode not in ('RGB','RGBA','L','LA'): img=img.convert('RGBA')
            interp=Image.Resampling.NEAREST if kind=='mers' else Image.Resampling.LANCZOS
            up=img.resize((target,target),interp)
            # PBR mask channels and heightmaps should not be artistically recolored.
            if kind!='albedo':
                data=up
            else:
                rgba=np.asarray(up.convert('RGBA'),dtype=np.float32).copy()
                seed=int(hashlib.sha256(name.encode()).hexdigest()[:14],16)
                broad=noise_tile(target,seed,32)
                fine=noise_tile(target,seed^398120,128)
                # Preserve luminance/hue so tinting and default Minecraft style work.
                amount=17 if ('dirt' in stem or 'stone' in stem or 'sand' in stem or 'gravel' in stem) else 12
                combined=amount*(.6*broad+.4*fine)
                if 'grass' in stem or 'leaves' in stem:
                    # Keep biome-tinted grayscale albedo compatible.
                    combined*=.65
                rgba[:,:,:3]=np.clip(rgba[:,:,:3]+combined[:,:,None],0,255)
                data=Image.fromarray(rgba.astype('uint8'),'RGBA')
                if img.mode=='RGB': data=data.convert('RGB')
                if img.mode=='L': data=data.convert('L')
            buf=io.BytesIO()
            if name.lower().endswith('.tga'): data.save(buf,format='TGA',rle=True)
            else: data.save(buf,format='PNG',compress_level=6)
            return buf.getvalue(),target,kind
    except Exception as exc:
        raise RuntimeError(f'Error processing {name}: {exc}') from exc

def build(source,dest):
    out=pathlib.Path(dest)
    out.parent.mkdir(parents=True,exist_ok=True)
    counts={'hi_res_albedo':0,'hi_res_pbr':0,'root_texture_entries':0,'removed_cloud_files':0,'files':0}
    with zipfile.ZipFile(source) as original:
        # Root resources first, then chosen VH subpack. No inherited 16px variant can override it.
        source_names=original.namelist()
        mapping={}
        for name in source_names:
            if name.startswith('subpacks/'): continue
            if name.endswith('/'): continue
            if remove_cloud(name):
                counts['removed_cloud_files']+=1
                continue
            mapping[name]=name
        for name in source_names:
            if not name.startswith('subpacks/vh/'): continue
            if name.endswith('/'): continue
            output_name=name[len('subpacks/vh/'):]
            if remove_cloud(output_name):
                counts['removed_cloud_files']+=1
                continue
            # Overlay the chosen Vanilla Clouds PBR variant at root.
            mapping[output_name]=name
        with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as packed:
            for dest_name,src_name in sorted(mapping.items()):
                content=original.read(src_name)
                if dest_name=='manifest.json':
                    m=json.loads(content.decode('utf-8-sig'))
                    m.pop('subpacks',None)
                    m['header']['name']='BSLB Xbox Sharp Core PBR - Vanilla Clouds'
                    m['header']['description']='Sharp core PBR textures at pack root; vanilla clouds; Xbox test edition'
                    m['header']['uuid']=str(uuid.uuid5(uuid.NAMESPACE_URL,'bslb-xbox-sharp-core-root-v3'))
                    m['header']['version']=[3,0,0]
                    m['header']['min_engine_version']=[1,21,120]
                    for i,mod in enumerate(m.get('modules',[])):
                        mod['uuid']=str(uuid.uuid5(uuid.NAMESPACE_URL,f'bslb-xbox-sharp-root-v3-module-{i}'))
                        mod['version']=[3,0,0]
                    m['capabilities']=['pbr']
                    content=json.dumps(m,ensure_ascii=False,indent=2).encode()
                elif dest_name.startswith('textures/blocks/'):
                    result=render(dest_name,content)
                    if result:
                        content,side,kind=result
                        if kind=='albedo': counts['hi_res_albedo']+=1
                        else: counts['hi_res_pbr']+=1
                    counts['root_texture_entries']+=1
                packed.writestr(dest_name,content)
                counts['files']+=1
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None
        m=json.loads(z.read('manifest.json'))
        assert not m.get('subpacks'), 'Subpack accidentally retained'
        assert any(x.startswith('textures/blocks/grass_top.') for x in z.namelist())
        assert not any(remove_cloud(x) for x in z.namelist())
        assert counts['hi_res_albedo']>=100, 'Missing core texture improvements'
        assert counts['hi_res_pbr']>=100, 'Missing PBR overlays'
    counts['bytes']=out.stat().st_size
    report=out.with_suffix('.report.json')
    report.write_text(json.dumps(counts,indent=2)+'\n')
    print('SHARP_ROOT_PACK_OK '+json.dumps(counts,sort_keys=True))
if __name__=='__main__':
    if len(sys.argv)!=3: raise SystemExit('usage: sharp_core.py original.mcpack output.mcpack')
    build(sys.argv[1],sys.argv[2])
