import json, pathlib, uuid, zipfile, sys
src, dst = map(pathlib.Path, sys.argv[1:3])
dst.parent.mkdir(parents=True,exist_ok=True)
removed = []
with zipfile.ZipFile(src) as z, zipfile.ZipFile(dst,"w") as out:
    for info in z.infolist():
        n=info.filename
        if n=="textures/environment/clouds.png" or n.endswith("/textures/environment/clouds.png") or "/textures/environment/overworld_cubemap/" in n or n=="cubemaps/default_cubemap.json":
            removed.append(n)
            continue
        data=z.read(info)
        if n=="manifest.json":
            m=json.loads(data)
            m["header"]["name"]="BSLB 4K - Vanilla Clouds"
            m["header"]["uuid"]=str(uuid.uuid5(uuid.NAMESPACE_URL,"bslb-4k-vanilla-clouds-header-v1"))
            for i,mod in enumerate(m.get("modules",[])):
                mod["uuid"]=str(uuid.uuid5(uuid.NAMESPACE_URL,f"bslb-4k-vanilla-clouds-module-{i}-v1"))
            data=json.dumps(m,ensure_ascii=False,indent=2).encode()
        out.writestr(info,data)
with zipfile.ZipFile(dst) as z:
    assert z.testzip() is None
    assert not any(n.endswith("/textures/environment/clouds.png") or "/textures/environment/overworld_cubemap/" in n for n in z.namelist())
print("Removed sky overrides:",len(removed),"output:",dst)
