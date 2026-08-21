#!/usr/bin/env python3
"""Stamp a Google Sheets document ID into every workflow.

n8n cannot resolve an expression in a resource-locator at design time, so a
documentId built from a Config value leaves the node unable to load the sheet's
columns - and the write silently maps nothing. Binding the id literally is what
actually works, so it is set here, once, across every file.

    python3 scripts/set-sheet-id.py 11kVd4FGR1vI8H8EVQ3_o2m0qzHMfMS_-xLgMgTLBH68
    python3 scripts/set-sheet-id.py --reset          # back to the placeholder
"""
import json, glob, sys, re

PLACEHOLDER = "PUT_YOUR_GOOGLE_SHEET_ID_HERE"

def main():
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(1)
    arg = sys.argv[1].strip()
    sheet_id = PLACEHOLDER if arg == "--reset" else arg

    if sheet_id != PLACEHOLDER:
        # accept a full URL and pull the id out of it
        m = re.search(r"/spreadsheets/d/([a-zA-Z0-9_-]+)", sheet_id)
        if m:
            sheet_id = m.group(1)
        if not re.fullmatch(r"[a-zA-Z0-9_-]{30,}", sheet_id):
            print(f"'{sheet_id}' does not look like a spreadsheet id.")
            print("Expected the long string between /d/ and /edit in the sheet's URL.")
            sys.exit(1)

    total = 0
    for path in sorted(glob.glob("workflows/*.json")):
        wf = json.load(open(path))
        touched = 0
        for node in wf["nodes"]:
            if node["type"] not in ("n8n-nodes-base.googleSheets",
                                    "n8n-nodes-base.googleSheetsTool"):
                continue
            doc = node.get("parameters", {}).get("documentId")
            if isinstance(doc, dict):
                doc["value"] = sheet_id
                doc["mode"] = "id"
                touched += 1
        if touched:
            json.dump(wf, open(path, "w"), indent=2, ensure_ascii=False)
            print(f"  {path.split('/')[-1]:52} {touched:2} node(s)")
            total += touched
    print(f"\nSet {total} node(s) to {sheet_id}")
    print("Re-import the workflows in n8n for this to take effect.")

if __name__ == "__main__":
    main()
