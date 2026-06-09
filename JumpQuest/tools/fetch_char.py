#!/usr/bin/env python3
# a.json(maplestory.io 캐릭터 export) → 게임에 필요한 모든 모션 프레임을 PNG로 받아옴.
# 프레임 수는 내용 해시로 자동 감지(중복=끝). 정렬은 별도(Swift).
import json, urllib.parse, urllib.request, hashlib, os, sys
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A=json.load(open(os.path.join(ROOT,"a.json")))
sel=A["selectedItems"]
# 아이템: itemId/region/version (per-item alpha 등 modifier는 API가 무시 → 불투명 유지)
items=[{"itemId":v["id"],"region":v.get("region","GMS"),"version":v.get("version","217")} for v in sel.values()]
pe=",".join(urllib.parse.quote(json.dumps(i)) for i in items)
RAW=os.path.join(ROOT,"tools","fetched_char","raw"); os.makedirs(RAW,exist_ok=True)
RESIZE="2"
def fetch(action,frame):
    u=f"https://maplestory.io/api/character/{pe}/{action}/{frame}?showears=false&resize={RESIZE}&renderMode=Full"
    req=urllib.request.Request(u,headers={"User-Agent":"Mozilla/5.0"})
    try: return urllib.request.urlopen(req,timeout=40).read()
    except Exception as e: return None
# action -> 받을 프레임들(자동감지: 최대 6까지, 해시 중복 시 멈춤)
ACTIONS=["stand1","walk1","jump","prone","rope","swingT1"]
manifest={}
for a in ACTIONS:
    seen=set(); frames=[]
    for f in range(0,6):
        d=fetch(a,f)
        if d is None: break
        h=hashlib.md5(d).hexdigest()
        if h in seen:  # 클램프/루프 → 끝
            break
        seen.add(h)
        p=os.path.join(RAW,f"{a}_{f}.png"); open(p,"wb").write(d)
        frames.append(f)
    manifest[a]=frames
    print(f"{a}: {len(frames)} frames {frames}")
json.dump(manifest, open(os.path.join(RAW,"manifest.json"),"w"))
print("MANIFEST", json.dumps(manifest))
