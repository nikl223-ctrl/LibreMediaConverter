#!/usr/bin/env python3
"""Check real user-supplied rescue-game formats on an ephemeral Windows runner.

Reads city.v, temporarily XOR-decodes it, tests a few DDS textures and decodes
selected FMOD FSB4 subsongs to temporary WAV files. Publishes only format,
dimensions, file lengths, cue names and validation results, never asset bytes.
"""
from __future__ import annotations
import argparse
import io
import json
import pathlib
import re
import struct
import subprocess
import tempfile
import wave
import zipfile
from collections import Counter

DDS_NAMES = [
    "textures/buildings/brick_red_diff.dds",
    "textures/buildings/city_hr1_var01_diff.dds",
    "textures/buildings/Gehwege.dds",
    "textures/vehicles/RTW/aussen_1.dds",
    "textures/vehicles/RTW/cockpit_1.dds",
    "textures/vehicles/RTW/lights_1.dds",
]
SOUND_MAP = {
    "siren": [r"Spielerfahrzeug_Sirene_Loop_V",r"Sirene"],
    "idle_engine": [r"RTW_NEU_Leerlauf_01",r"RTW_Leerlauf"],
    "driving_engine": [r"RTW_NEU_Normal_01",r"RTW_NEU_Langsam_01"],
    "high_rpm": [r"RTW_NEU_Hoch_04"],
}
MODELS = [
    "models/vehicle/RTW/chassis.Model",
    "models/vehicle/RTW/cockpit.Model",
    "models/vehicle/RTW/rtw_wheel.Model",
    "models/vehicle/RTW/chassis.VMESH",
    "models/buildings/emergency_station/ES_small_inside.VMESH",
]

def stream_headers(data: bytes) -> list[dict]:
    if data[:4] != b"FSB4":
        return []
    count = struct.unpack_from("<I", data, 4)[0]
    sample_headers_len = struct.unpack_from("<I", data, 8)[0]
    if count < 1 or count > 1000 or sample_headers_len > len(data):
        raise ValueError("Implausible FSB4 bank header")
    pos=0x30
    streams=[]
    for i in range(count):
        if pos + 0x50 > len(data):
            break
        header_len=struct.unpack_from("<H", data, pos)[0]
        if header_len<0x50 or header_len>10000 or pos+header_len>len(data):
            break
        # FSB4 stores up to 30 bytes of the stream name.
        name=data[pos+2:pos+32].split(b"\x00",1)[0].decode("latin1",errors="replace")
        streams.append({"index":i+1,"name":name,"sample_header_bytes":header_len})
        pos+=header_len
    return streams

def inspect(city:pathlib.Path, vgmstream:pathlib.Path|None):
    out={
        "source":"user-shared Rettungswagen-Simulator 2012 city.v",
        "original_files_published":False,
        "decoded_assets_published":False,
        "dds_test":{},
        "fsb4_test":{},
        "mesh_headers":{},
        "city_model_count":0,
    }
    key=bytes.maketrans(bytes(range(256)),bytes(i^0x55 for i in range(256)))
    with tempfile.TemporaryDirectory(prefix="vision_proof_") as temp:
        root=pathlib.Path(temp)
        decoded=root/"city.zip"
        with city.open("rb") as src,decoded.open("wb") as dest:
            while True:
                buf=src.read(8*1024*1024)
                if not buf: break
                dest.write(buf.translate(key))
        with zipfile.ZipFile(decoded) as archive:
            manifest={path.lower():path for path in archive.namelist()}
            out["city_model_count"]=sum(name.lower().endswith((".vmesh",".model")) for name in archive.namelist())
            from PIL import Image, UnidentifiedImageError
            for key_name in DDS_NAMES:
                actual=manifest.get(key_name.lower())
                if not actual:
                    out["dds_test"][key_name]={"found":False}
                    continue
                data=archive.read(actual)
                try:
                    with Image.open(io.BytesIO(data)) as image:
                        image.load()
                        image.convert("RGB").resize((256,256)).save(root/"texture_proof.webp",format="WEBP")
                        out["dds_test"][key_name]={
                            "found":True,"decoded":True,
                            "dimensions":list(image.size),"pixel_format":str(image.mode),
                            "mobile_webp_conversion_ok":(root/"texture_proof.webp").stat().st_size>100
                        }
                except Exception as error:
                    out["dds_test"][key_name]={"found":True,"decoded":False,"error_type":type(error).__name__}
            model_files=[]
            for name in MODELS:
                actual=manifest.get(name.lower())
                if actual: model_files.append(actual)
            # Use concrete known models and VMesh samples, not files from elsewhere.
            if len(model_files)<3:
                model_files += [n for n in archive.namelist() if n.lower().endswith((".vmesh",".model"))][:5]
            for name in model_files[:10]:
                data=archive.open(name).read(2048)
                out["mesh_headers"][name]={
                    "full_bytes":archive.getinfo(name).file_size,
                    "header_hex":data[:80].hex(" "),
                    "header_ascii":"".join(chr(c) if 32<=c<=126 else "." for c in data[:100]),
                    "strings":re.findall(r"[ -~]{8,100}",data.decode("latin1",errors="ignore"))[:8]
                }
            for bank in ("sfx/RTW_2011_bank00.fsb","sfx/RTW_2011_bank01.fsb"):
                actual=manifest.get(bank.lower())
                if not actual: continue
                data=archive.read(actual)
                streams=stream_headers(data)
                bank_path=root/pathlib.Path(bank).name
                bank_path.write_bytes(data)
                matches=[]
                for cue,candidates in SOUND_MAP.items():
                    for info in streams:
                        if any(re.search(pattern,info["name"],re.I) for pattern in candidates):
                            record={"name":info["name"],"index":info["index"],"cue":cue}
                            if vgmstream is not None and vgmstream.is_file():
                                wav_path=root/f"decoded_{cue}.wav"
                                command=[str(vgmstream),"-i","-s",str(info["index"]),"-o",str(wav_path),str(bank_path)]
                                try:
                                    p=subprocess.run(command,capture_output=True,text=True,timeout=80)
                                    if p.returncode==0 and wav_path.is_file():
                                        with wave.open(str(wav_path),"rb") as wav:
                                            record["decoded"]=True
                                            record["seconds"]=round(wav.getnframes()/wav.getframerate(),2)
                                            record["channels"]=wav.getnchannels()
                                            record["sample_rate"]=wav.getframerate()
                                    else:
                                        record["decoded"]=False
                                        record["decoder_error"]=(p.stderr or p.stdout)[-160:]
                                except Exception as e:
                                    record["decoded"]=False
                                    record["decoder_error_type"]=type(e).__name__
                                wav_path.unlink(missing_ok=True)
                            matches.append(record)
                            break
                out["fsb4_test"][bank]={"samples_count":len(streams),"named_audio_test":matches}
                bank_path.unlink(missing_ok=True)
        decoded.unlink(missing_ok=True)
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--city",required=True)
    ap.add_argument("--vgmstream",default="")
    ap.add_argument("--out",required=True)
    args=ap.parse_args()
    data=inspect(pathlib.Path(args.city),pathlib.Path(args.vgmstream) if args.vgmstream else None)
    out=pathlib.Path(args.out)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(data,indent=2,ensure_ascii=False),encoding="utf8")
    print("ORIGINAL_DDS_TEST",json.dumps(data["dds_test"],ensure_ascii=False),flush=True)
    print("ORIGINAL_FSB_TEST",json.dumps(data["fsb4_test"],ensure_ascii=False),flush=True)
    print("ORIGINAL_MESH_HEADERS",json.dumps(data["mesh_headers"],ensure_ascii=False)[:4500],flush=True)

if __name__=="__main__":
    main()
