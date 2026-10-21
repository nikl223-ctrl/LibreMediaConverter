#!/usr/bin/env python3
"""Select and extract a single legitimate PC Episode I scene from GOG DAT.

Run only on ephemeral GitHub workers; never commit original assets. The
new-engine pilot is not the complete original gameplay or level logic.
"""
import argparse
import json
from pathlib import Path
from ttdat import DatArchive

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--archive",required=True)
    parser.add_argument("--output",required=True)
    parser.add_argument("--manifest",required=True)
    args=parser.parse_args()
    archive=DatArchive(args.archive)
    candidates=[entry for entry in archive.entries
        if entry.path.upper().endswith("_PC.GSC")
        and "EPISODE_I" in entry.path.upper()
        and "INTRO" not in entry.path.upper()
        and 100_000 < entry.size < 125_000_000]
    # Start from Episode I Negotiations; prefer main stage rather than a cutscene.
    def rank(e):
        upper=e.path.upper().replace("\\","/")
        priorities=(0 if "/NEGOTIATIONS/" in upper else 1,
            0 if "NEGOTIATIONS_PC.GSC" in upper else 1,
            0 if 2_000_000<=e.size<=75_000_000 else 1,
            e.size)
        return priorities
    candidates.sort(key=rank)
    if not candidates:
        raise RuntimeError("No exportable PC Episode I scene under size limit")
    chosen=candidates[0]
    payload=archive.read(chosen)
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_bytes(payload)
    report={"source":"EPISODE_I.DAT","original_relative_path":chosen.path,
        "decoded_size":len(payload),"stored_size":chosen.zsize,
        "all_scene_candidates":len(candidates),"format":"Original PC GSC",
        "purpose":"experimental private glTF Godot physics prototype",
        "gameplay_status":"not reconstructed"}
    Path(args.manifest).write_text(json.dumps(report,indent=2),encoding="utf-8")
    print("EPISODE_I_SELECTED_SCENE="+chosen.path)
    print("EPISODE_I_SELECTED_SCENE_BYTES="+str(len(payload)))
    print("EPISODE_I_SCENE_CANDIDATES="+str(len(candidates)))
    print("OWNED_PC_EPISODE_SCENE_EXTRACT=PASS")

if __name__=="__main__":
    main()
