#!/usr/bin/env python3
# maplestory.io 캐릭터 렌더 API로 장비 조합을 서버 합성해 받아옴(앵커 자동).
# 사용: render_char.py <itemIds,쉼표> <action> <frame> <out.png> [resize]
import sys, json, urllib.parse, urllib.request
def char_url(ids, action="stand1", frame="0", resize="2"):
    items = ",".join(urllib.parse.quote(json.dumps({"itemId":i,"region":"GMS","version":"214"})) for i in ids)
    return f"https://maplestory.io/api/character/{items}/{action}/{frame}?showears=false&resize={resize}&renderMode=Full"
def fetch(url, out):
    req=urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    d=urllib.request.urlopen(req, timeout=40).read(); open(out,"wb").write(d); return len(d)
if __name__=="__main__":
    ids=[int(x) for x in sys.argv[1].split(",")]
    action=sys.argv[2] if len(sys.argv)>2 else "stand1"
    frame=sys.argv[3] if len(sys.argv)>3 else "0"
    out=sys.argv[4] if len(sys.argv)>4 else "/tmp/char.png"
    resize=sys.argv[5] if len(sys.argv)>5 else "2"
    url=char_url(ids,action,frame,resize)
    try:
        n=fetch(url,out); print(f"OK {n}b -> {out}")
    except Exception as e:
        print("ERR", e)
