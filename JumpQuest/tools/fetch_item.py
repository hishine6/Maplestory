#!/usr/bin/env python3
# maplestory.io 에서 아이템의 프레임별 레이어 + 정렬정보를 받아 staging 폴더에 저장.
# 사용: python3 fetch_item.py <itemId> [region] [version]
import sys, os, json, base64, urllib.request

itemId = sys.argv[1] if len(sys.argv)>1 else "1302000"
region = sys.argv[2] if len(sys.argv)>2 else "GMS"
version = sys.argv[3] if len(sys.argv)>3 else "214"
out = f"/Users/tony/test_app/JumpQuest/tools/fetched/{itemId}"
os.makedirs(out, exist_ok=True)

url = f"https://maplestory.io/api/{region}/{version}/item/{itemId}"
print("fetching", url)
req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0 JumpQuest"})
data = json.load(urllib.request.urlopen(req, timeout=30))

name = (data.get("description") or {}).get("name", "?")
slot = (data.get("typeInfo") or {})
fb = data.get("frameBooks", {})
manifest = {"id": itemId, "name": name, "typeInfo": slot, "actions": {}}
count = 0
for action, book in fb.items():
    frames = book.get("frames", [])
    manifest["actions"][action] = []
    for i, fr in enumerate(frames):
        for layer, lv in (fr.get("effects") or {}).items():
            img = lv.get("image")
            if not img: continue
            png = base64.b64decode(img)
            fn = f"{action}_{i}_{layer}.png"
            open(os.path.join(out, fn), "wb").write(png)
            manifest["actions"][action].append({
                "frame": i, "layer": layer, "file": fn,
                "origin": lv.get("origin"),
                "handOffset": (lv.get("mapOffset") or {}).get("hand"),
                "position": lv.get("position"),
            })
            count += 1
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), ensure_ascii=False, indent=2)
print(f"'{name}' → {count} layer PNGs, actions: {list(fb.keys())}")
print("saved to", out)
