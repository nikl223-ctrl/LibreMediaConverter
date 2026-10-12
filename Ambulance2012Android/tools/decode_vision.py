#!/usr/bin/env python3
"""Inspect an original Vision city.v archive encoded using XOR 0x55.

A non-executing file format inspector. Does not publish or copy game binaries,
audio, images or models into the repository. Deletes the decoded temporary ZIP
after logging an inventory of filenames and file types.
"""
from __future__ import annotations
import argparse
import collections
import json
import pathlib
import tempfile
import zipfile
import time
import os
import re
import xml.etree.ElementTree as ET

def decrypt(source: pathlib.Path, output: pathlib.Path) -> None:
    key=0x55
    translator=bytes.maketrans(bytes(range(256)),bytes((x ^ key) for x in range(256)))
    t=time.monotonic()
    with source.open("rb") as inp, output.open("wb") as out:
        while True:
            block=inp.read(8*1024*1024)
            if not block:break
            out.write(block.translate(translator))
    print(f"ZIP_XOR_DECODE_DONE seconds={time.monotonic()-t:.1f} bytes={output.stat().st_size}",flush=True)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input",required=True)
    p.add_argument("--out",required=True)
    opts=p.parse_args()
    origin=pathlib.Path(opts.input)
    report=pathlib.Path(opts.out)
    results={
        "source":"user supplied city.v from Google Drive",
        "xor_key_hex":"0x55",
        "source_size":origin.stat().st_size,
        "archive_format":"unknown",
        "zip_valid":False,
        "top_files":[],
        "extensions":{},
        "entry_count":0,
        "total_uncompressed_bytes":0,
        "original_content_published":False
    }
    # Keep decrypted original only on the temporary GitHub runner.
    with tempfile.TemporaryDirectory(prefix="vision_decode_") as tmp:
        temp=pathlib.Path(tmp)/"decoded_city.zip"
        decrypt(origin,temp)
        with temp.open("rb") as test:
            if test.read(4)!=b"PK\x03\x04":
                raise ValueError("XOR key did not generate expected ZIP header")
        results["archive_format"]="XOR 0x55 encoded ZIP"
        with zipfile.ZipFile(temp,"r",allowZip64=True) as z:
            entries=z.infolist()
            counts=collections.Counter()
            results["entry_count"]=len(entries)
            results["total_uncompressed_bytes"]=sum(i.file_size for i in entries)
            for item in entries:
                extension=pathlib.PurePosixPath(item.filename.replace("\\","/")).suffix.lower() or "<none>"
                counts[extension]+=1
            results["extensions"]=dict(counts.most_common(100))
            results["top_files"]=[
                {"name":item.filename,"compressed":item.compress_size,"uncompressed":item.file_size,"method":item.compress_type}
                for item in sorted(entries,key=lambda i:i.file_size,reverse=True)[:100]
            ]
            results["zip_valid"]=True
            # Identify scene and vehicle metadata without including game files in outputs.
            results["scene_metadata"]={}
            for candidate in ("city.xml","cluster.xml","vehicles/rtw.xvd","vehicles/ktw.xvd","vehicles/rtw-2.xvd","vehicles/vehicle-list.txt","ui/mainmenu.xml"):
                if candidate not in z.namelist():
                    continue
                item=z.getinfo(candidate)
                stats={"uncompressed_bytes":item.file_size,"first_bytes_hex":z.open(candidate).read(32).hex(" ")}
                if candidate.endswith(".txt"):
                    stats["first_lines"]=[line[:130] for line in z.read(candidate)[:1000].decode("utf-8",errors="replace").splitlines()[:5]]
                else:
                    tag_counts=collections.Counter()
                    attribute_examples={}
                    try:
                        with z.open(candidate) as content:
                            for _,element in ET.iterparse(content,events=("start",)):
                                tag=element.tag.split("}")[-1]
                                tag_counts[tag]+=1
                                if tag not in attribute_examples:
                                    attribute_examples[tag]=list(element.attrib)[:10]
                                element.clear()
                                if sum(tag_counts.values())>1800:
                                    break
                        stats["parsed_as_xml"]=True
                        stats["xml_element_counts_first_1800"]=dict(tag_counts.most_common(30))
                        stats["xml_attribute_keys_sample"]=dict(list(attribute_examples.items())[:15])
                    except Exception as e:
                        stats["parsed_as_xml"]=False
                        stats["parse_error_type"]=type(e).__name__
                results["scene_metadata"][candidate]=stats
            results["vehicle_physics_summary"]={}
            for vehicle_id in ("rtw","ktw","rtw-2","k1","k2"):
                path=f"vehicles/{vehicle_id}.xvd"
                if path not in z.namelist():
                    continue
                try:
                    root=ET.fromstring(z.read(path))
                    wanted=("MeshFile","CollisionMeshFile","CockpitFile","InteriorFile","WheelFile","Mass",
                            "MassCenterOffset","SteerScaleFactor","MaximumSteerAngle","SuspensionSpring",
                            "SuspensionDamper","SuspensionTarget","SuspensionTravel","Radius")
                    numbers={}
                    for tag in wanted:
                        elements=root.findall(".//"+tag)
                        values=[("".join(x.itertext())).strip()[:130] for x in elements[:4]]
                        if values:
                            numbers[tag]=values
                    results["vehicle_physics_summary"][vehicle_id]=numbers
                except Exception as e:
                    results["vehicle_physics_summary"][vehicle_id]={"error":type(e).__name__}
            print("VISION_VEHICLE_PHYSICS=",json.dumps(results["vehicle_physics_summary"],ensure_ascii=False)[:8500],flush=True)
            results["vehicle_files"]=[x.filename for x in entries if x.filename.lower().startswith("vehicles/") and not x.is_dir()][:80]
            results["sound_files"]=[x.filename for x in entries if x.filename.lower().startswith("sfx/") and x.filename.lower().endswith((".fsb",".wav",".ogg",".fev"))][:60]
            results["sound_bank_headers"]={}
            for bank in ("sfx/RTW_2011_bank00.fsb","sfx/RTW_2011_bank01.fsb","sfx/RTW_2011.fev"):
                if bank not in z.namelist():
                    continue
                with z.open(bank) as sound_file:
                    header=sound_file.read(96)
                    header_2m=sound_file.read(2*1024*1024)
                results["sound_bank_headers"][bank]={
                    "header_hex":header[:48].hex(" "),
                    "header_ascii":"".join(chr(b) if 32<=b<=126 else "." for b in header[:64]),
                    "size":z.getinfo(bank).file_size,
                    "likely_sfx_label_words":[word.decode("latin1") for word in
                        re.findall(rb"[A-Za-z0-9_()\\- ]{4,70}",header_2m)
                        if any(phrase in word.lower() for phrase in
                            [b"horn",b"siren",b"motor",b"engine",b"standgas",b"diesel",b"rtw",b"drive",b"alarm",b"signal"] )][:35]
                }
            print("VISION_SOUND_HEADERS=",json.dumps(results["sound_bank_headers"])[:5000],flush=True)
            results["ambulance_models"]=[x.filename for x in entries if ("rtw" in x.filename.lower() or "ktw" in x.filename.lower() or "ambulance" in x.filename.lower()) and x.filename.lower().endswith((".vmesh",".model",".vmesh_data",".dds"))][:50]
            print("VISION_CITY_SCENE_META=",json.dumps(results["scene_metadata"],ensure_ascii=False)[:5500],flush=True)
            print("VISION_CITY_SOUND_LIST=",json.dumps(results["sound_files"][:20]),flush=True)
            print("VISION_CITY_AMBULANCE_MODELS=",json.dumps(results["ambulance_models"][:20]),flush=True)
            print("VISION_ARCHIVE_VALID_ZIP entries=",len(entries),flush=True)
            print("VISION_ARCHIVE_EXTENSIONS=",json.dumps(dict(counts.most_common(25))),flush=True)
            print("VISION_ARCHIVE_FIRST_FILES=",json.dumps([i.filename for i in entries[:50]]),flush=True)
            print("VISION_ARCHIVE_LARGEST=",json.dumps([i.filename for i in sorted(entries,key=lambda i:i.file_size,reverse=True)[:15]]),flush=True)
    report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding="utf-8")
    print("VISION_ARCHIVE_REPORT=",report,flush=True)

if __name__=="__main__":
    main()
