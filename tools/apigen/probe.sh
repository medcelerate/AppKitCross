#!/bin/bash
# Records enum raw values, option-set bits and string constants from the real SDK.
# macOS only. Output: api-inventory/AppKit.values.json
#
# AppKit is weak-linked because the SDK may declare constants newer than the running OS
# without availability annotations; such keys crash at runtime, are dropped, and the probe
# is rebuilt until it runs to completion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
python3 -I "$ROOT/tools/apigen/apigen.py" --emit-probe "$TMP/probe.swift"
python3 -I - "$TMP/probe.swift" <<'PY'
import re, sys
p = sys.argv[1]
src = open(p).read()
src = re.sub(r'results\[("[^"]+")\] = rv\(',
             r'FileHandle.standardError.write((\1 + "\\n").data(using: .utf8)!); results[\1] = rv(', src)
open(p, "w").write(src)
PY
for i in $(seq 1 40); do
  # Lines that fail to type-check (generic protocols etc.) are dropped first.
  if ! xcrun swiftc -O -suppress-warnings -Xlinker -weak_framework -Xlinker AppKit -o "$TMP/probe" "$TMP/probe.swift" 2> "$TMP/err.log"; then
    grep -E "^$TMP/probe.swift:[0-9]+:[0-9]+: error:" "$TMP/err.log" | cut -d: -f2 | sort -un > "$TMP/bad.txt"
    python3 -I - "$TMP/probe.swift" "$TMP/bad.txt" <<'PY'
import sys
p, badp = sys.argv[1], sys.argv[2]
bad = set(int(x) for x in open(badp) if x.strip())
lines = open(p).read().split("\n")
open(p, "w").write("\n".join(("    // DROPPED (does not compile)" if (i + 1) in bad else l) for i, l in enumerate(lines)))
PY
    continue
  fi
  if "$TMP/probe" > "$TMP/values.json" 2> "$TMP/keys.log"; then
    cp "$TMP/values.json" "$ROOT/api-inventory/AppKit.values.json"
    echo "wrote api-inventory/AppKit.values.json after $i runs"
    exit 0
  fi
  last="$(tail -1 "$TMP/keys.log")"
  echo "dropping $last (missing on this OS)"
  python3 -I - "$TMP/probe.swift" "$last" <<'PY'
import sys
p, key = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
open(p, "w").write("\n".join(("    // DROPPED (missing on this OS): " + key) if ('results["%s"]' % key) in l else l for l in lines))
PY
done
echo "probe did not converge" >&2
exit 1
