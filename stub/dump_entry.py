#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from cpio_tool import read_entries

entries, _ = read_entries(sys.argv[1])
for e in entries:
    if e["name"] == sys.argv[2]:
        print("fields", [f.decode() for f in e["fields"]])
        print("raw_name", e["raw_name"])
        print("content", e["content"])
