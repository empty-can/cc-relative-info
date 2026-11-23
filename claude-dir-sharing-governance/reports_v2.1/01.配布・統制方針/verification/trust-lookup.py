"""~/.claude.json の projects から、指定した文字列を含むキーの trust の記録を表示する（読むだけ）。

usage: python -I -X utf8 trust-lookup.py <パスの一部> [...]
"""
import json
import os
import sys

path = os.path.expanduser("~/.claude.json")
try:
    d = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"  ~/.claude.json を読めない: {e}")
    sys.exit(0)
pats = [a.lower().replace("\\", "/") for a in sys.argv[1:]]
hits = 0
for k, v in d.get("projects", {}).items():
    kl = k.lower().replace("\\", "/")
    if any(p in kl for p in pats):
        hits += 1
        print(f"  projects[{k!r}].hasTrustDialogAccepted = {v.get('hasTrustDialogAccepted')}")
if not hits:
    print(f"  projects に {sys.argv[1:]} を含むキーは無い")
