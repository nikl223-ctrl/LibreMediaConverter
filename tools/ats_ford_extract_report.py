#!/usr/bin/env python3
"""Create a shareable numeric physics report from locally extracted SCS game defs.

Never copies full copyrighted SCS assets or complete definition source files
into the report or GitHub artifacts.
"""
import json
import re
from pathlib import Path

roots = [Path("extracted/ford"), Path("extracted/def")]
needle = ("ford", "mustang", "bronco", "victoria", "f150", "car/", "car\\", "physics", "vehicle", "chassis")
terms = ("kerb", "weight", "mass", "spring", "suspension", "travel", "steer", "brake", "tire", "wheel", "friction", "torque", "ratio", "damp", "power", "axle", "roll", "drag", "center", "rpm", "stiffness", "resistance")
number = re.compile(r"^[-+\d.eE,\s()]+$")
files=[]
summary={"file_count":0,"definition_files":0,"interesting_files":[],"numeric_parameters":[],"warnings":[]}
for root in roots:
    if not root.exists():
        summary["warnings"].append("Missing extractor output: "+str(root))
        continue
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        summary["file_count"] += 1
        relative = str(p).replace("\\","/")
        low = relative.lower()
        if not p.suffix.lower() in (".sii",".sui"):
            continue
        summary["definition_files"] += 1
        if not any(k in low for k in needle):
            continue
        if len(summary["interesting_files"]) < 4000:
            summary["interesting_files"].append({"path":relative,"size":p.stat().st_size})
        if p.stat().st_size > 2_000_000:
            continue
        try:
            content = p.read_text(encoding="utf-8",errors="replace")
            params=[]
            for raw in content.splitlines():
                line=raw.split("#",1)[0].strip()
                if ":" not in line:
                    continue
                key,val=line.split(":",1)
                val=val.strip().strip('"')
                if any(s in key.lower() for s in terms) and len(val)<160 and number.fullmatch(val) and val:
                    params.append({"key":key.strip(),"value":val})
            if params and len(summary["numeric_parameters"]) < 2500:
                summary["numeric_parameters"].append({"path":relative,"values":params[:100]})
        except Exception as e:
            summary["warnings"].append(relative+" "+str(e)[:120])
Path("ats-ford-extracted-report.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
print("ATS_FORD_EXTRACT_SUMMARY",json.dumps({k:summary[k] for k in ("file_count","definition_files","warnings")},ensure_ascii=False),flush=True)
for item in summary["interesting_files"][:120]:
    print("FORD_DEF_FILE",json.dumps(item,ensure_ascii=False),flush=True)
for item in summary["numeric_parameters"][:120]:
    print("FORD_PHYSICS_VALUES",json.dumps(item,ensure_ascii=False),flush=True)
