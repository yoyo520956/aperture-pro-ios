#!/usr/bin/env python3
"""从 Apple 文档 JSON 里提取 Photos 类的准确 Swift 签名"""
import json, urllib.request

UA = {"User-Agent": "Mozilla/5.0"}
for cls in ["phassetcreationrequest", "phassetchangerequest"]:
    url = f"https://developer.apple.com/tutorials/data/documentation/photos/{cls}.json"
    try:
        req = urllib.request.Request(url, headers=UA)
        data = json.loads(urllib.request.urlopen(req, timeout=40).read().decode())
    except Exception as e:
        print(f"{cls}: FETCH FAIL {e}")
        continue
    print(f"===== {cls} =====")
    refs = data.get("references", {})
    for key, v in refs.items():
        t = v.get("title", "")
        frag = v.get("fragments", [])
        txt = "".join(f.get("text", "") for f in frag)
        if "creationRequestForAsset" in t or "creationRequestForAsset" in txt or "addResource" in t:
            print(" *", t, "|", txt[:160])
    # topicSections 里 methods
    for sec in data.get("topicSections", []):
        if sec.get("title") in ("Instance Methods", "Class Methods", "Methods"):
            for ident in sec.get("identifiers", []):
                r = refs.get(ident, {})
                frag = "".join(f.get("text", "") for f in r.get("fragments", []))
                print("  -", r.get("title", ""), "->", frag[:200])
