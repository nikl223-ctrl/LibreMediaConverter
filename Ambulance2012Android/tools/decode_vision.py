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
            print("VISION_ARCHIVE_VALID_ZIP entries=",len(entries),flush=True)
            print("VISION_ARCHIVE_EXTENSIONS=",json.dumps(dict(counts.most_common(25))),flush=True)
            print("VISION_ARCHIVE_FIRST_FILES=",json.dumps([i.filename for i in entries[:50]]),flush=True)
            print("VISION_ARCHIVE_LARGEST=",json.dumps([i.filename for i in sorted(entries,key=lambda i:i.file_size,reverse=True)[:15]]),flush=True)
    report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding="utf-8")
    print("VISION_ARCHIVE_REPORT=",report,flush=True)

if __name__=="__main__":
    main()
