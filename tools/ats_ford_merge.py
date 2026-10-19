#!/usr/bin/env python3
"""Merge finished ATS TAR scan reports into metadata-only physics inventory."""
import json
from pathlib import Path

reports=[]
for p in Path("downloaded").rglob("worker-*.json"):
    try:
        reports.append(json.loads(p.read_text(encoding="utf-8")))
    except (OSError, ValueError) as e:
        print("Could not read report:",str(p),str(e))
reports.sort(key=lambda r:r.get("worker",-1))
entries=[v for r in reports for v in r.get("entries",[])]
archives=[v for r in reports for v in r.get("archive_formats",[])]
physics=[v for r in reports for v in r.get("physics_values",[])]
candidates=[v for v in entries if any(x in v.get("path","").lower() for x in ("ford","road_trip","roadtrip","car","vehicle","physics","def.scs",".scs"))]
summary={
 "workers_reporting":len(reports),
 "workers_completed":sum(r.get("status")=="complete" for r in reports),
 "total_bytes_scanned":sum(r.get("scanned_bytes",0) for r in reports),
 "all_tar_entries":len(entries),
 "candidate_entries":candidates,
 "scs_archives":archives,
 "physics_values":physics,
 "failures":[{"worker":r.get("worker"),"errors":r.get("errors",[])} for r in reports if r.get("status")!="complete"]
}
Path("ats-ford-physics-report.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
print("ATS_MERGE_STATUS:", summary["workers_completed"], "/", summary["workers_reporting"],"workers,",summary["total_bytes_scanned"],"bytes scanned")
print("ATS_ALL_TAR_ENTRIES:",len(entries),"SCS archives:",len(archives),"numeric physics values:",len(physics))
for entry in candidates[:250]:
    print("ATS_CANDIDATE:",json.dumps(entry,ensure_ascii=False))
for entry in archives[:250]:
    print("ATS_SCS_FORMAT:",json.dumps(entry,ensure_ascii=False))
for entry in physics[:250]:
    print("ATS_PHYSICS_VALUE:",json.dumps(entry,ensure_ascii=False))
for item in summary["failures"]:
    print("ATS_WORKER_ERROR:",json.dumps(item,ensure_ascii=False))
