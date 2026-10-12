#!/usr/bin/env python3
"""Binary inspection of the user-provided 2012 Vision game archive.
Does not execute, extract, or redistribute any game content.
Only outputs magic offsets, likely resource types and aggregate metadata.
"""
import argparse
import json
import mmap
import re
from collections import Counter
from pathlib import Path

MAGIC = {
    "DDS_Texture": b"DDS ",
    "PNG_Image": b"\x89PNG\r\n\x1a\n",
    "JPEG_Image": b"\xff\xd8\xff",
    "RIFF_AudioOrContainer": b"RIFF",
    "Ogg_Audio": b"OggS",
    "FSB4_AudioBank": b"FSB4",
    "FSB5_AudioBank": b"FSB5",
    "ZIP_Archive": b"PK\x03\x04",
    "KTX_Texture": b"\xabKTX",
    "VPK_Archive": b"VPK",
    "XML_Document": b"<?xml",
    "WAV_Format": b"WAVE",
    "PNG_ResourceName": b".png",
    "DDS_ResourceName": b".dds",
    "WAV_ResourceName": b".wav",
    "OGG_ResourceName": b".ogg",
    "Vmesh_ResourceName": b".vmesh",
    "Vision_Identifier": b"Vision",
    "VArchive_Identifier": b"VArchive",
}
EXT = re.compile(rb"(?:[A-Za-z0-9_\-./\\]{5,120})\.(?:dds|png|jpg|jpeg|tga|wav|ogg|fmod|mesh|vmesh|model|anim|vmat|vtex|xml|vscene|vmap|texture|vcolmesh)\b", re.I)
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--input",required=True)
    ap.add_argument("--out",required=True)
    args=ap.parse_args()
    filename=Path(args.input)
    results={"filename":"city.v","size_bytes":filename.stat().st_size,"format":"unknown (Vision proprietary data)","signatures":{},"possible_asset_paths":[]}
    with filename.open("rb") as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as mm:
        header=mm[:256]
        results["header_hex"]=header[:96].hex(" ")
        results["header_ascii"]="".join(chr(c) if 32<=c<=126 else "." for c in header[:96])
        results["zero_fraction_first_1mb"]=round(mm[:min(len(mm),1048576)].count(b"\x00") / float(min(len(mm),1048576)),6)
        for label, needle in MAGIC.items():
            hits=[]
            pos=0
            while len(hits)<256:
                p=mm.find(needle,pos)
                if p<0: break
                hits.append(p)
                pos=p+len(needle)
            results["signatures"][label]={"count_at_least":len(hits),"first_positions":hits[:24],"capped":len(hits)==256}
        sample = mm[:min(len(mm),64*1024*1024)]
        paths=[x.decode("latin-1",errors="ignore") for x in EXT.findall(sample)]
        results["possible_asset_paths"]=list(dict.fromkeys(paths))[:80]
        results["possible_resource_extension_counts"]=dict(Counter(p.rsplit(".",1)[-1].lower() for p in paths).most_common())
    out=Path(args.out)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(results,indent=2),encoding="utf8")
    print("VISION_CITY_HEADER_HEX:",results["header_hex"])
    print("VISION_CITY_HEADER_ASCII:",results["header_ascii"])
    print("VISION_CITY_SIGNATURE_COUNTS:",{k:v["count_at_least"] for k,v in results["signatures"].items() if v["count_at_least"]})
    print("VISION_CITY_POSSIBLE_PATHS:",results["possible_asset_paths"][:18])
    print("VISION_CITY_REPORT:",out)
if __name__=="__main__":
    main()
