#!/usr/bin/env python3
"""Private-only, user-supplied Vision game asset converter.

Never run this on a public repository. Original commercial data are only read
from a temporarily downloaded city.v; selected JPEG/WebP texture derivatives
and decoded WAV files stay inside a PRIVATE GitHub Actions workflow.
No original .exe/.dll is executed. No proprietary VMESH/MODEL is claimed to
be decoded or converted.
"""
from __future__ import annotations
import argparse
import io
import json
import os
import pathlib
import re
import struct
import subprocess
import tempfile
import zipfile
from PIL import Image

DDS_MAP={
    "brick_wall.webp":"textures/buildings/brick_red_diff.dds",
    "brick_wall2.webp":"textures/buildings/brick_red_2_diff.dds",
    "city_highrise.webp":"textures/buildings/city_hr1_var01_diff.dds",
    "sidewalk.webp":"textures/buildings/Gehwege.dds",
    "rtw_exterior.webp":"textures/vehicles/RTW/aussen_1.dds",
    "rtw_exterior_secondary.webp":"textures/vehicles/RTW/aussen_2.dds",
    "rtw_cockpit.webp":"textures/vehicles/RTW/cockpit_1.dds",
    "rtw_interior.webp":"textures/vehicles/RTW/front_innen_2.dds",
    "rtw_lights.webp":"textures/vehicles/RTW/lights_1.dds",
    "rtw2_exterior.webp":"textures/vehicles/rtw-2/aussen_1.dds"
}
ORIGINAL_AUDIO={
    "siren.wav":[r"Spielerfahrzeug_Sirene_Loop_V",r"sirene_loop"],
    "engine_idle.wav":[r"RTW_NEU_Leerlauf_01",r"RTW_Niedrig_02"],
    "engine_normal.wav":[r"RTW_NEU_Normal_01",r"RTW_NEU_Langsam_01"],
    "engine_high.wav":[r"RTW_NEU_Hoch_04"]
}

def fsb4_stream_names(data: bytes) -> list[dict]:
    if not data.startswith(b"FSB4"):
        return []
    num=struct.unpack_from("<I",data,4)[0]
    sample_headers_len=struct.unpack_from("<I",data,8)[0]
    if num<1 or num>3000 or sample_headers_len>len(data):
        return []
    pos=0x30
    names=[]
    for i in range(num):
        if pos+0x50>len(data):
            break
        header_size=struct.unpack_from("<H",data,pos)[0]
        if header_size<0x50 or header_size>500 or pos+header_size>len(data):
            break
        name=data[pos+2:pos+32].split(b"\0")[0].decode("latin-1",errors="replace").strip()
        names.append({"index":i+1,"name":name})
        pos+=header_size
    return names

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--city",required=True)
    ap.add_argument("--out",required=True)
    ap.add_argument("--vgmstream",required=True)
    opts=ap.parse_args()
    if os.environ.get("GITHUB_REPOSITORY_PRIVATE","").lower()!="true":
        raise SystemExit("SECURITY: original commercial asset import requires private GitHub repository.")
    output=pathlib.Path(opts.out)
    output.mkdir(parents=True,exist_ok=True)
    city=pathlib.Path(opts.city)
    if not city.is_file() or city.stat().st_size<100_000_000:
        raise SystemExit("Source archive missing or unexpectedly small.")
    decoder=pathlib.Path(opts.vgmstream)
    if not decoder.is_file():
        raise SystemExit("vgmstream-cli decoder is missing; cannot decode FSB4.")
    mapped={}
    failures={}
    sound_metadata=[]
    trans=bytes.maketrans(bytes(range(256)),bytes(i^0x55 for i in range(256)))
    with tempfile.TemporaryDirectory(prefix="original_private_") as td:
        tmp=pathlib.Path(td)
        decoded=tmp/"city.zip"
        with city.open("rb") as f,decoded.open("wb") as of:
            while data:=f.read(8*1024*1024):
                of.write(data.translate(trans))
        with zipfile.ZipFile(decoded) as archive:
            for name,src in DDS_MAP.items():
                try:
                    data=archive.read(src)
                    with Image.open(io.BytesIO(data)) as image:
                        image.load()
                        image=image.convert("RGB")
                        original_size=image.size
                        image.thumbnail((2048,2048),Image.Resampling.LANCZOS)
                        image.save(output/name,format="WEBP",quality=85,method=4)
                    mapped[name]={"source":src,"dimensions_original":original_size}
                except Exception as exc:
                    failures[name]=type(exc).__name__
            for bank_name in ("sfx/RTW_2011_bank00.fsb","sfx/RTW_2011_bank01.fsb"):
                bank_data=archive.read(bank_name)
                names=fsb4_stream_names(bank_data)
                bank_path=tmp/pathlib.Path(bank_name).name
                bank_path.write_bytes(bank_data)
                print("PRIVATE_FSB_STREAM_NAMES",bank_name,[(x["index"],x["name"]) for x in names[:50]],flush=True)
                for info in names:
                    sound_metadata.append({"bank":bank_name,"index":info["index"],"name":info["name"]})
                for output_name,patterns in ORIGINAL_AUDIO.items():
                    if (output/output_name).exists():
                        continue
                    matches=[]
                    for pattern in patterns:
                        matches=[item for item in names if re.search(pattern,item["name"],re.I)]
                        if matches:
                            break
                    if not matches:
                        continue
                    selected=matches[0]
                    cmd=[str(decoder),"-i","-s",str(selected["index"]),"-o",str(output/output_name),str(bank_path)]
                    print("Decoding",selected["name"],"->",output_name,flush=True)
                    p=subprocess.run(cmd,capture_output=True,text=True,timeout=150)
                    if p.returncode!=0 or not (output/output_name).is_file():
                        failures[output_name]=(p.stderr or p.stdout)[-300:]
                        continue
                    mapped[output_name]={"bank":bank_name,"stream_name":selected["name"],"index":selected["index"],"bytes":(output/output_name).stat().st_size}
                bank_path.unlink()
    result={"private_build_only":True,"source":"Google Drive user-provided city.v","files":mapped,"errors":failures,"fsb_stream_names":sound_metadata,"original_3d_models_imported":False,"original_world_imported":False,"commercial_assets_republished_to_public_repo":False}
    (output/"asset_manifest.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    print("PRIVATE_CONVERSION_RESULTS",json.dumps({k:v for k,v in mapped.items()}),flush=True)
    for item in ("siren.wav","engine_idle.wav","engine_normal.wav"):
        if not (output/item).is_file():
            raise SystemExit("Missing essential authentic audio sample: "+item)
    print("PRIVATE_ORIGINAL_SOUND_IMPORT_PASS",flush=True)

if __name__=="__main__":
    main()
