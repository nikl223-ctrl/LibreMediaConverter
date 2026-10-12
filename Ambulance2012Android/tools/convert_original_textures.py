#!/usr/bin/env python3
"""Prepare user-owned original PC-game DDS material previews for a PRIVATE build.

Input stays in the ephemeral runner; only converted artwork is written to OUT.
The caller must require a PRIVATE GitHub repository and the user's permission.
Vision 3D MODEL/VMESH binaries need a separate genuine geometry converter.
"""
import argparse
import io
import json
import pathlib
import tempfile
import zipfile
from PIL import Image

TEXTURES={
    "brick_wall.webp":"textures/buildings/brick_red_diff.dds",
    "brick_wall2.webp":"textures/buildings/brick_red_2_diff.dds",
    "sidewalk.webp":"textures/buildings/Gehwege.dds",
    "rtw_exterior.webp":"textures/vehicles/RTW/aussen_1.dds",
    "rtw_exterior_secondary.webp":"textures/vehicles/RTW/aussen_2.dds",
    "rtw_cockpit.webp":"textures/vehicles/RTW/cockpit_1.dds",
    "rtw_interior.webp":"textures/vehicles/RTW/front_innen_2.dds",
    "rtw_lights.webp":"textures/vehicles/RTW/lights_1.dds",
    "rtw2_exterior.webp":"textures/vehicles/rtw-2/aussen_1.dds"
}

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument("--source",required=True)
    ap.add_argument("--out",required=True)
    args=ap.parse_args()
    src=pathlib.Path(args.source)
    out=pathlib.Path(args.out)
    out.mkdir(parents=True,exist_ok=True)
    trans=bytes.maketrans(bytes(range(256)),bytes(i^0x55 for i in range(256)))
    converted={}
    missing=[]
    unsupported=[]
    with tempfile.TemporaryDirectory(prefix="private_vision_") as dirname:
        decoded=pathlib.Path(dirname)/"city.zip"
        with src.open("rb") as fi,decoded.open("wb") as fo:
            while chunk:=fi.read(8*1024*1024):
                fo.write(chunk.translate(trans))
        with zipfile.ZipFile(decoded) as z:
            for output_name,original in TEXTURES.items():
                if original not in z.namelist():
                    missing.append(original)
                    continue
                try:
                    raw=z.read(original)
                    with Image.open(io.BytesIO(raw)) as image:
                        image.load()
                        base=image.convert("RGB")
                        original_size=base.size
                        base.thumbnail((2048,2048),Image.Resampling.LANCZOS)
                        target=out/output_name
                        base.save(target,format="WEBP",quality=87,method=5)
                        converted[output_name]={"original":original,"source_size":original_size,"mobile_size":base.size,"bytes":target.stat().st_size}
                except Exception as e:
                    unsupported.append({"source":original,"error_type":type(e).__name__})
    manifest={
        "non_public_private_build_only":True,
        "converted_textures":converted,
        "missing_files":missing,
        "unsupported_files":unsupported,
        "original_models_converted":False,
        "original_sounds_converted":False,
        "copyright_and_license":"User must have the rights required for any redistribution, even through private artifacts."
    }
    (out/"original_assets_manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print("PRIVATE_ASSET_TEXTURES_CONVERTED",len(converted))
    print("PRIVATE_ASSET_MISSING",missing)
    print("PRIVATE_ASSET_UNSUPPORTED",unsupported)
    if len(converted)<2:
        raise SystemExit("Too few DDS materials converted; ensure Pillow DDS support.")
if __name__=="__main__":
    main()
