#!/usr/bin/env python3
"""拉取 Aperture Pro 最近一次 CI 的 artifact 日志并抽出 error 行"""
import json, os, sys, zipfile, urllib.request

REPO = "yoyo520956/aperture-pro-ios"
TOK = os.environ.get("GITHUB_TOKEN", "")
H = {"Authorization": "Bearer " + TOK, "User-Agent": "minis"}

def get(url):
    r = urllib.request.Request(url, headers=H)
    return urllib.request.urlopen(r, timeout=60).read()

runs = json.loads(get(f"https://api.github.com/repos/{REPO}/actions/runs?per_page=5"))
for run in runs["workflow_runs"][:5]:
    print("RUN", run["id"], run["head_sha"][:10], run["status"], run["conclusion"], run["created_at"])

target = runs["workflow_runs"][0]
rid = target["id"]
print("=== using run", rid, target["head_sha"][:10], target["conclusion"], "===")

arts = json.loads(get(f"https://api.github.com/repos/{REPO}/actions/runs/{rid}/artifacts"))
if not arts["artifacts"]:
    print("NO ARTIFACTS")
    sys.exit(0)
for a in arts["artifacts"]:
    print("ART", a["id"], a["name"], a["size_in_bytes"])

a = arts["artifacts"][0]
import subprocess
blob = subprocess.run(["curl","-s","-L","-H","Authorization: Bearer "+TOK, f"https://api.github.com/repos/{REPO}/actions/artifacts/{a['id']}/zip","-o",f"/tmp/art_{a['id']}.zip"], capture_output=True).stdout or b""
zpath = f"/tmp/art_{a['id']}.zip"
open(zpath, "wb").write(blob)
out = "/tmp/art_out"
os.makedirs(out, exist_ok=True)
with zipfile.ZipFile(zpath) as z:
    z.extractall(out)
print("extracted to", out)
for root, dirs, files in os.walk(out):
    for f in files:
        p = os.path.join(root, f)
        print("FILE", p, os.path.getsize(p))
