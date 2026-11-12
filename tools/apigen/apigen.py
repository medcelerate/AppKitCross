#!/usr/bin/env python3
"""
apigen: generate AppKit stubs, a probe program and a coverage report from symbol graphs.

Inputs (see tools/apigen/extract.sh and probe.sh):
  api-inventory/raw/<Module>.symbols.json, <Module>@<Other>.symbols.json
  api-inventory/AppKit.values.json           (raw values / string constants, from probe)
  api-inventory/Foundation-windows-types.json (top-level types corelibs Foundation provides)
  tools/apigen/config.json                   (handwritten / pending / skip lists)

Outputs:
  Sources/AppKit/Generated/*.swift   compiled stubs
  Stubs/Pending/AppKit/*.swift       stubs for types listed as pending in config.json
  Stubs/Seeds/AppKit/*.swift         full stubs for hand-written types (reference only)
  docs/API-COVERAGE.md               coverage report
  --emit-probe <file>                Swift program that prints raw values (macOS only)
"""
import argparse
import collections
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "api-inventory", "raw")

STRIP_ATTRS = re.compile(
    r"@(?:objc|IBAction|IBOutlet|IBInspectable|IBSegueAction|NSCopying|NSManaged|"
    r"preconcurrency|_nonSendable|objcMembers|nonobjc|NSApplicationMain|"
    r"_disfavoredOverload|backDeployed|_spi|abi|_alwaysEmitIntoClient|inlinable|usableFromInline)(?:\([^)]*\))?\s*"
)
RETURN_RE = re.compile(r"\)\s*(?:async\s+)?(?:(?:re)?throws(?:\([^)]*\))?\s+)?->\s*(.+)$")

# Protocols that do not need to be defined by us because the stdlib / Foundation has them.
STDLIB_PROTOCOLS = {
    "s:SQ": "Equatable", "s:SH": "Hashable", "s:SY": "RawRepresentable",
    "s:s8SendableP": "Sendable", "s:s9OptionSetP": "OptionSet", "s:s5ErrorP": "Error",
    "s:SE": "Encodable", "s:Se": "Decodable", "s:s23CustomStringConvertibleP": "CustomStringConvertible",
    "s:s28CustomDebugStringConvertibleP": "CustomDebugStringConvertible",
    "s:s7CVarArgP": "CVarArg", "s:s16SendableMetatypeP": "SendableMetatype",
    "s:s8CopyableP": "Copyable", "s:s9EscapableP": "Escapable",
    "s:s10SetAlgebraP": "SetAlgebra", "s:s25ExpressibleByArrayLiteralP": "ExpressibleByArrayLiteral",
    "s:s26ExpressibleByStringLiteralP": "ExpressibleByStringLiteral",
    "s:s43ExpressibleByExtendedGraphemeClusterLiteralP": "ExpressibleByExtendedGraphemeClusterLiteral",
    "s:s33ExpressibleByUnicodeScalarLiteralP": "ExpressibleByUnicodeScalarLiteral",
    "s:s10ComparableP": "Comparable", "s:SL": "Comparable", "s:s12IdentifiableP": "Identifiable",
    "s:ST": "Sequence", "s:Sl": "Collection", "s:SK": "BidirectionalCollection",
    "s:Sk": "RandomAccessCollection", "s:s17ReferenceConvertibleP": "ReferenceConvertible",
    "s:s16_ObjectiveCBridgeableP": "_ObjectiveCBridgeable",
}
FOUNDATION_PROTOCOLS = {
    "c:objc(pl)NSObject": "NSObjectProtocol", "c:objc(pl)NSCoding": "NSCoding",
    "c:objc(pl)NSSecureCoding": "NSSecureCoding", "c:objc(pl)NSCopying": "NSCopying",
    "c:objc(pl)NSMutableCopying": "NSMutableCopying",
}
# Conformances a class gets for free from NSObject; never re-declare on subclasses.
NSOBJECT_CONFORMANCES = {"c:objc(pl)NSObject", "s:SQ", "s:SH", "s:s7CVarArgP",
                         "s:s23CustomStringConvertibleP", "s:s28CustomDebugStringConvertibleP",
                         "s:s8SendableP", "s:s16SendableMetatypeP", "s:s8CopyableP", "s:s9EscapableP"}
STRUCT_KEEP_CONFORMANCES = {"s:SQ", "s:SH", "s:s8SendableP", "s:s5ErrorP", "s:SE", "s:Se",
                            "s:s10ComparableP", "s:SL"}

MODULE_PREFIX_HINTS = [
    ("CI", "CoreImage"), ("MTL", "Metal"), ("MTK", "MetalKit"), ("UT", "UniformTypeIdentifiers"),
    ("CV", "CoreVideo"), ("IOSurface", "IOSurface"), ("AV", "AVFoundation"), ("CK", "CloudKit"),
    ("IN", "Intents"), ("NSManagedObject", "CoreData"), ("NSFetch", "CoreData"), ("NSEntity", "CoreData"),
    ("CL", "CoreLocation"), ("CM", "CoreMedia"), ("PK", "PencilKit"), ("SK", "SpriteKit"),
    ("SCN", "SceneKit"), ("QL", "QuickLook"), ("Symbol", "Symbols"), ("NSSymbol", "Symbols"),
    ("os_", "os"), ("OS", "os"), ("CG", "CoreGraphics"), ("CA", "QuartzCore"), ("CT", "CoreText"),
    ("CF", "CoreFoundation"), ("Image", "DeveloperToolsSupport"), ("Color", "DeveloperToolsSupport"),
]


def owner_kind_is_protocol(ctx):
    return ctx.get("kind") == "protocol"


def frag_text(frags):
    return "".join(f["spelling"] for f in frags)


class Inventory:
    def __init__(self, module):
        self.module = module
        self.symbols = {}          # precise -> symbol (module's own + its extensions of other types)
        self.foreign_ext = {}      # precise -> symbol, from Module@Other graphs
        self.other_symbols = {}    # precise -> symbol, from other modules (Foundation, QuartzCore, ...)
        self.members = collections.defaultdict(list)
        self.superclass = {}
        self.conformances = collections.defaultdict(list)
        self.protocol_parents = collections.defaultdict(list)
        self.overrides = set()
        self.override_target = {}
        self.known_kinds = {}      # precise -> swift.class / swift.struct ...
        self.optional_req = {}
        self.required_by = {}
        self.known_types = {}      # precise -> (module, path) for every type in every loaded graph
        self.by_path = {}

    def load_graph(self, path, foreign):
        with open(path) as f:
            g = json.load(f)
        mod = g["module"]["name"]
        for s in g["symbols"]:
            pid = s["identifier"]["precise"]
            if s["kind"]["identifier"].startswith("swift.") and s["kind"]["identifier"] in (
                    "swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                self.known_types.setdefault(pid, (mod, tuple(s["pathComponents"])))
                self.known_kinds.setdefault(pid, s["kind"]["identifier"])
            if foreign:
                self.foreign_ext[pid] = s
            else:
                self.symbols[pid] = s
                self.by_path.setdefault(tuple(s["pathComponents"]), []).append(s)
        for r in g["relationships"]:
            k, src, dst = r["kind"], r["source"], r["target"]
            if k == "memberOf":
                self.members[dst].append(src)
            elif k == "inheritsFrom":
                self.superclass[src] = dst
            elif k == "conformsTo":
                self.conformances[src].append(dst)
            elif k == "overrides":
                self.overrides.add(src)
                self.override_target[src] = dst
            elif k == "optionalRequirementOf":
                self.optional_req[src] = dst
                if src not in self.members[dst]:
                    self.members[dst].append(src)
            elif k == "requirementOf":
                self.required_by[src] = dst
                if src not in self.members[dst]:
                    self.members[dst].append(src)

    def load_other_module_types(self, path):
        with open(path) as f:
            g = json.load(f)
        mod = g["module"]["name"]
        for s in g["symbols"]:
            if s["kind"]["identifier"] in ("swift.class", "swift.struct", "swift.enum",
                                           "swift.protocol", "swift.typealias"):
                self.known_types.setdefault(s["identifier"]["precise"], (mod, tuple(s["pathComponents"])))
                self.known_kinds.setdefault(s["identifier"]["precise"], s["kind"]["identifier"])
        for s in g["symbols"]:
            self.other_symbols.setdefault(s["identifier"]["precise"], s)
        for r in g["relationships"]:
            k, src, dst = r["kind"], r["source"], r["target"]
            if k == "memberOf":
                self.members[dst].append(src)
            elif k == "inheritsFrom":
                self.superclass.setdefault(src, dst)
            elif k == "conformsTo":
                self.conformances[src].append(dst)
            elif k == "optionalRequirementOf":
                self.optional_req[src] = dst
                if src not in self.members[dst]:
                    self.members[dst].append(src)
            elif k == "requirementOf":
                self.required_by[src] = dst
                if src not in self.members[dst]:
                    self.members[dst].append(src)

    def sym(self, pid):
        return self.symbols.get(pid) or self.foreign_ext.get(pid) or self.other_symbols.get(pid)

    def own(self, pid):
        return pid in self.symbols


class Generator:
    def __init__(self, inv, config, values, foundation_types, args):
        self.inv = inv
        self.config = config
        self.values = values
        self.foundation_types = set(foundation_types)
        self.handwritten = set(config.get("handwritten", []))
        self._handwritten_keys_cache = {}
        self.pending = set(config.get("pending", []))
        self.skip_types = set(config.get("skipTypes", []))
        self.skip_members = set(config.get("skipMembers", []))
        self.cg_types = set(config.get("coreGraphicsTypes", []))
        self.qc_types = set(config.get("quartzCoreTypes", []))
        self.ct_types = set(config.get("coreTextTypes", []))
        self.report = []
        self.probe_entries = []
        self._own_keys_cache = {}
        self._extension_members = set()   # protocol members declared in extensions (not requirements)
        self.args = args

    # ---------- availability of referenced types ----------
    def type_availability(self, pid, spelling):
        """Return None if usable on Windows, else a reason string."""
        if pid is None:
            return None
        if pid in ("c:objc(pl)NSObject", "c:objc(cs)NSObject", "s:10ObjectiveC8SelectorV", "c:@S@_NSZone",
                   "s:10ObjectiveC8ObjCBoolV", "c:@T@NSZone", "c:@T@SEL"):
            return None
        # Geometry and time scalars live in Foundation on Windows (corelibs) whatever module
        # Apple's SDK attributes them to.
        if spelling in ("CGFloat", "CGRect", "CGPoint", "CGSize", "CGVector", "CGAffineTransform",
                        "CFTimeInterval", "NSRect", "NSPoint", "NSSize", "CGRectEdge"):
            return None
        if pid.startswith("s:"):
            kt = self.inv.known_types.get(pid)
            if kt is None:
                m = re.match(r"s:(\d+)", pid)
                if m:
                    n = int(m.group(1))
                    modname = pid[2 + len(m.group(1)):2 + len(m.group(1)) + n]
                    if modname in ("Foundation",):
                        return None if spelling.split(".")[0] in self.foundation_types else "Foundation.%s not in corelibs" % spelling
                    return "%s.%s" % (modname, spelling)
                if pid.startswith("s:So"):
                    return "unresolved ObjC type %s" % spelling
                return None   # s:S..., s:s... = Swift stdlib / _Concurrency
            mod, path = kt
        else:
            kt = self.inv.known_types.get(pid)
            if kt is None:
                return "unknown module (%s %s)" % (self.guess_module(spelling), spelling)
            mod, path = kt
        top = path[0]
        if mod == self.inv.module:
            if top in self.skip_types:
                return "skipped type %s" % top
            if top in self.pending:
                return "pending type %s" % top
            return None
        if mod == "Foundation":
            if top in self.foundation_types:
                return None
            return "Foundation.%s not in corelibs" % top
        if mod == "CoreGraphics":
            return None if top in self.cg_types else "CoreGraphics.%s not implemented" % top
        if mod == "QuartzCore":
            return None if top in self.qc_types else "QuartzCore.%s not implemented" % top
        if mod == "CoreText":
            return None if top in self.ct_types else "CoreText.%s not implemented" % top
        if mod in ("Swift", "_Concurrency", "Dispatch", "ObjectiveC"):
            if mod == "ObjectiveC" and top not in ("NSObject", "NSObjectProtocol", "Selector", "NSZone", "ObjCBool"):
                return "ObjectiveC.%s" % top
            return None
        return "%s.%s" % (mod, top)

    def guess_module(self, name):
        for prefix, mod in MODULE_PREFIX_HINTS:
            if name.startswith(prefix):
                return mod
        return "?"

    def member_blockers(self, sym):
        reasons = []
        seen = set()
        frags = list(sym.get("declarationFragments", []))
        for f in frags:
            if f["kind"] == "typeIdentifier":
                pid = f.get("preciseIdentifier")
                r = self.type_availability(pid, f["spelling"])
                if r and r not in seen:
                    seen.add(r)
                    reasons.append(r)
        return reasons

    # ---------- declaration text ----------
    def decl_text(self, sym):
        t = frag_text(sym["declarationFragments"])
        t = re.sub(r"@abi\((?:[^()]|\([^()]*\))*\)\s*", "", t)
        t = STRIP_ATTRS.sub("", t)
        t = re.sub(r"\bdynamic\s+", "", t)
        t = re.sub(r"\boptional\s+", "", t)
        t = re.sub(r"\bunowned(?:\([^)]*\))?\s+var\b", "var", t)
        t = re.sub(r"\bweak\s+var\b", "var", t)
        t = t.replace("class let ", "static let ")
        t = re.sub(r": (U?Int(?:8|16|32|64)?) = \[\]", r": \1", t)
        t = re.sub(r"\s+", " ", t).strip()
        return t

    NSOBJECT_KEYS = {("method", "isEqual(_:)"), ("property", "hash"), ("property", "description"),
                     ("property", "debugDescription"), ("init", "init()"), ("method", "copy()"),
                     ("method", "mutableCopy()"), ("method", "isProxy()"), ("property", "superclass"),
                     ("property", "classForCoder"), ("method", "isKind(of:)"), ("method", "isMember(of:)"),
                     ("method", "conforms(to:)"), ("method", "responds(to:)"), ("method", "self()"),
                     ("property", "hashValue"), ("method", "didChangeValue(forKey:)"),
                     ("method", "willChangeValue(forKey:)"), ("method", "value(forKey:)"),
                     ("method", "setValue(_:forKey:)"), ("method", "value(forKeyPath:)"),
                     ("method", "setValue(_:forKeyPath:)"), ("method", "setNilValueForKey(_:)"),
                     ("method", "value(forUndefinedKey:)"), ("method", "setValue(_:forUndefinedKey:)"),
                     ("method", "observeValue(forKeyPath:of:change:context:)"),
                     ("method", "addObserver(_:forKeyPath:options:context:)"),
                     ("method", "removeObserver(_:forKeyPath:)"), ("method", "removeObserver(_:forKeyPath:context:)"),
                     ("method", "mutableArrayValue(forKey:)"), ("method", "mutableSetValue(forKey:)"),
                     ("method", "mutableOrderedSetValue(forKey:)"), ("method", "dictionaryWithValues(forKeys:)"),
                     ("method", "setValuesForKeys(_:)"), ("method", "awakeFromNib()"),
                     ("method", "prepareForInterfaceBuilder()"), ("method", "forwardingTarget(for:)"),
                     ("method", "doesNotRecognizeSelector(_:)"), ("method", "perform(_:)"),
                     ("method", "perform(_:with:)"), ("method", "perform(_:with:with:)")}

    @staticmethod
    def member_key(sym):
        k = sym["kind"]["identifier"]
        cat = {"swift.method": "method", "swift.func.op": "method", "swift.init": "init",
               "swift.property": "property", "swift.type.method": "type.method",
               "swift.type.property": "type.property", "swift.subscript": "subscript"}.get(k)
        if cat is None:
            return None
        name = sym["pathComponents"][-1]
        if cat == "init" and name.startswith("init?("):
            name = "init(" + name[len("init?("):]
        if cat == "init" and name.startswith("init!("):
            name = "init(" + name[len("init!("):]
        return (cat, name)

    def will_emit(self, sym):
        pid = sym["identifier"]["precise"]
        if "::SYNTHESIZED::" in pid or self.unavailable(sym):
            return False
        if ".".join(sym["pathComponents"]) in self.skip_members:
            return False
        if sym.get("swiftExtension", {}).get("constraints"):
            return False
        return not self.member_blockers(sym)

    def own_keys(self, type_pid, include_requirements=True):
        """Member keys this type itself provides (ignoring ancestors)."""
        if (type_pid, include_requirements) in self._own_keys_cache:
            return self._own_keys_cache[(type_pid, include_requirements)]
        keys = {}
        for mid in self.inv.members.get(type_pid, []):
            m = self.inv.sym(mid)
            if not m:
                continue
            key = self.member_key(m)
            if key is None:
                continue
            if self.inv.own(mid):
                if self.will_emit(m):
                    keys.setdefault(key, []).append(m)
            else:
                # Other module (Foundation / QuartzCore): assume present on Windows if the type is.
                keys.setdefault(key, []).append(m)
        if include_requirements and self.inv.known_kinds.get(type_pid) == "swift.class":
            for c in self.inv.conformances.get(type_pid, []):
                for rsym in self.protocol_requirements(c) + (self.ambiguous_defaults(type_pid, c) if self.inv.own(type_pid) else []):
                    key = self.member_key(rsym)
                    if key and self.will_emit(rsym) and not any(
                            self.normalized_signature(self.decl_text(x), strict=True) == self.normalized_signature(self.decl_text(rsym), strict=True)
                            for x in keys.get(key, [])):
                        keys.setdefault(key, []).append(rsym)
        self._own_keys_cache[(type_pid, include_requirements)] = keys
        return keys

    def ancestor_keys(self, type_pid):
        keys = {}
        for include_reqs in (False, True):
            sup = self.inv.superclass.get(type_pid)
            depth = 0
            while sup and depth < 20:
                for k, v in self.own_keys(sup, include_reqs).items():
                    keys.setdefault(k, []).extend(v)
                if not include_reqs:
                    kt = self.inv.known_types.get(sup)
                    if kt and kt[1][0] in self.handwritten:
                        for k, v in self.handwritten_keys(kt[1][0]).items():
                            keys.setdefault(k, []).extend(v)
                if sup == "c:objc(cs)NSObject":
                    break
                sup = self.inv.superclass.get(sup)
                depth += 1
        for k in self.NSOBJECT_KEYS:
            keys.setdefault(k, [None])
        return keys

    HANDWRITTEN_DECL_RE = re.compile(
        r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:open|public)\s+(?:override\s+)?(?:required\s+)?(?:(?P<static>static|class)\s+)?"
        r"(?:final\s+)?(?P<kind>func|var|let)\s+(?P<name>[A-Za-z_]\w*)(?P<rest>.*)$")

    def handwritten_keys(self, type_name):
        """Members a hand-written class declares in its own body (Sources/AppKit/Core), as
        synthetic symbols keyed like SDK members. The SDK lists NSView's accessibility
        methods only as protocol requirements, but the hand-written NSView declares them,
        so a generated subclass's stub for the same requirement must say `override`
        there (or stay a plain overload when the signature differs)."""
        if type_name in self._handwritten_keys_cache:
            return self._handwritten_keys_cache[type_name]
        keys = {}
        path = os.path.join(ROOT, "Sources", "AppKit", "Core", type_name + ".swift")
        if os.path.exists(path):
            depth = 0
            container = None          # "class" while inside the type's own body
            lines = open(path).read().split("\n")
            i = 0
            while i < len(lines):
                line = lines[i]
                stripped = line.strip()
                if depth == 0:
                    m = re.match(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:open|public|internal|final|private)\s+)*(class|extension)\s+(\w+)", stripped)
                    container = m.group(1) if m and m.group(2) == type_name else None
                elif depth == 1 and container == "class" and not stripped.startswith("//"):
                    m = self.HANDWRITTEN_DECL_RE.match(stripped)
                    if m:
                        name, kind, rest = m.group("name"), m.group("kind"), m.group("rest")
                        if kind == "func":
                            # Collect the signature up to the body (it may span lines).
                            sig = rest
                            j = i
                            while sig.count("(") > sig.count(")") and j + 1 < len(lines):
                                j += 1
                                sig += " " + lines[j].strip()
                            sig = re.sub(r"\s*\{.*$", "", sig).strip()
                            params = sig[1:sig.rfind(")")] if sig.startswith("(") else ""
                            labels = []
                            level = 0
                            cur = ""
                            for ch in params + ",":
                                if ch in "([<":
                                    level += 1
                                elif ch in ")]>":
                                    level -= 1
                                if ch == "," and level == 0:
                                    tok = cur.strip()
                                    if tok:
                                        labels.append(tok.split(":")[0].split()[0] + ":")
                                    cur = ""
                                else:
                                    cur += ch
                            key = (("type.method" if m.group("static") else "method"), name + "(" + "".join(labels) + ")")
                            decl = ("static " if m.group("static") else "") + "func " + name + sig
                        else:
                            key = (("type.property" if m.group("static") else "property"), name)
                            decl = ("static " if m.group("static") else "") + "var " + name + re.sub(r"\s*(?:\{.*|=.*)$", "", rest)
                        sym = {"kind": {"identifier": "swift." + key[0]}, "pathComponents": [type_name, key[1]],
                               "identifier": {"precise": "handwritten:" + type_name + "." + key[1]},
                               "declarationFragments": [{"kind": "text", "spelling": decl}]}
                        keys.setdefault(key, []).append(sym)
                depth += line.count("{") - line.count("}")
                i += 1
        self._handwritten_keys_cache[type_name] = keys
        return keys

    @staticmethod
    def normalized_signature(decl, strict=False):
        d = re.sub(r"^(?:@\w+(?:\([^)]*\))?\s+)*", "", decl)
        d = re.sub(r"\b(?:open|public|override|required|convenience|class|static|final|mutating)\s+", "", d)
        d = re.sub(r"\b(\w+) (\w+):", r"\1:", d)     # drop internal parameter names
        d = re.sub(r"\s*=\s*[^,)]+", "", d)           # drop default values
        for a, b in (("NSRectPointer", "UnsafeMutablePointer<NSRect>"), ("NSPointPointer", "UnsafeMutablePointer<NSPoint>"),
                     ("NSSizePointer", "UnsafeMutablePointer<NSSize>"), ("NSRangePointer", "UnsafeMutablePointer<NSRange>"),
                     ("NSRect", "CGRect"), ("NSPoint", "CGPoint"), ("NSSize", "CGSize"), ("NSInteger", "Int"), ("NSUInteger", "UInt")):
            d = d.replace(a, b)
        if not strict:
            d = d.replace("?", "").replace("!", "")    # optionality differences are override-compatible
        d = re.sub(r"\s+", " ", d).strip()
        return d

    def is_optional_requirement(self, sym):
        return sym["identifier"]["precise"] in self.inv.optional_req

    def unavailable(self, sym):
        for a in sym.get("availability", []):
            if a.get("isUnconditionallyUnavailable"):
                return True
            if a.get("domain") == "macOS" and a.get("isUnconditionallyUnavailable"):
                return True
        return False

    def doc_url(self, path):
        parts = [self.inv.module.lower()] + [p.lower() for p in path]
        return "https://developer.apple.com/documentation/" + "/".join(parts)

    @staticmethod
    def introduced(sym):
        for a in sym.get("availability", []):
            if a.get("domain") == "macOS" and a.get("introduced"):
                v = a["introduced"]
                return (v["major"], v.get("minor", 0))
        return None

    def availability_line(self, sym, indent, owner=None):
        v = self.introduced(sym)
        if not v or v < (10, 10):
            return []
        if owner is not None:
            ov = self.introduced(owner) or (10, 0)
            if v <= ov:
                return []
        return ["%s@available(macOS %d.%d, *)" % (indent, v[0], v[1])]

    def doc_lines(self, sym, indent, owner=None):
        lines = []
        dc = sym.get("docComment")
        if dc:
            for ln in dc["lines"][:12]:
                lines.append("%s/// %s" % (indent, ln["text"]))
        lines.append("%s/// - SeeAlso: %s" % (indent, self.doc_url(sym["pathComponents"])))
        lines += self.availability_line(sym, indent, owner)
        return lines

    def raw_value_for(self, path):
        v = self.values.get(".".join(path))
        if not v or v == "?":
            return None
        ty, _, val = v.partition("|")
        return ty, val

    @staticmethod
    def swift_literal(ty, val):
        if ty == "String":
            return json.dumps(val)
        if ty in ("Double", "Float", "CGFloat"):
            return val
        return val

    # ---------- member emission ----------
    def emit_member(self, sym, ctx, indent):
        """ctx: dict(kind=class|struct|enum|protocol|extension, access=open|public,
        owner_path=tuple, raw_type=str|None, in_protocol_ext=bool)"""
        kind = sym["kind"]["identifier"]
        pid = sym["identifier"]["precise"]
        path = tuple(sym["pathComponents"])
        name = path[-1]
        out = []
        if "::SYNTHESIZED::" in pid:
            return None, "synthesized"
        if self.unavailable(sym) and name != "wrappedValue":
            return None, "unavailable"
        if ".".join(path) in self.skip_members:
            return None, "config skipMembers"
        blockers = self.member_blockers(sym)
        decl = self.decl_text(sym)
        optional = (self.is_optional_requirement(sym) or ctx.get("force_optional", False)
                    or pid in self._extension_members) and kind != "swift.init"
        if owner_kind_is_protocol(ctx):
            decl = self.strip_defaults(decl)   # no default arguments in requirements
        if blockers:
            out.append("%s// SKIPPED (%s): %s" % (indent, "; ".join(blockers), decl))
            return out, "blocked"

        owner_kind = ctx["kind"]
        raw_type = ctx.get("raw_type")
        if pid in self.inv.override_target and kind in ("swift.property", "swift.type.property"):
            tgt = self.inv.sym(self.inv.override_target[pid])
            if tgt is not None:
                a = re.sub(r"^.*?(?:var|let) [^:]+: ", "", self.decl_text(sym))
                b = re.sub(r"^.*?(?:var|let) [^:]+: ", "", self.decl_text(tgt))
                a = re.sub(r" \{ get(?: set)? \}$", "", a); b = re.sub(r" \{ get(?: set)? \}$", "", b)
                if a != b:
                    out.append("%s// SKIPPED (override type %s differs from superclass %s): %s" % (indent, a, b, decl))
                    return out, "blocked"
                if decl.endswith("{ get set }") == self.decl_text(tgt).endswith("{ get set }") and tgt["pathComponents"][0] not in self.handwritten:
                    out.append("%s// INHERITED (identical redeclaration): %s" % (indent, decl))
                    return out, "inherited"
        is_static = bool(re.match(r"^(?:@\w+\s+)*(?:static|class) ", decl))
        access = ctx["access"]
        if owner_kind in ("struct", "enum", "extension_struct") or is_static:
            access = "public"
        if ctx.get("final"):
            access = "public"
        prefix = ""
        if owner_kind != "protocol":
            prefix = access + " "
            key = self.member_key(sym)
            anc = ctx.get("ancestor_keys", {})
            overriding = owner_kind == "class" and key is not None and key in anc
            parent = None
            if overriding:
                parents = anc.get(key) or [None]
                parent = parents[0]
                if parent is not None:
                    match = None
                    for cand in parents:
                        if cand is None:
                            continue
                        pd = self.decl_text(cand)
                        if self.is_override_compatible(child=decl, parent=pd):
                            match = cand
                            break
                    if match is None:
                        overriding = False      # a plain overload, not an override
                    else:
                        parent = match
            if overriding:
                if parent is None and kind == "swift.init" and decl.startswith("init?"):
                    out.append("%s// SKIPPED (failable init cannot override NSObject's non-failable init): %s" % (indent, decl))
                    return out, "blocked"
                if parent is not None:
                    pdecl = self.decl_text(parent)
                    if name in ("init?(coder:)", "init(coder:)"):
                        pattrs, pbody = self.split_attrs(pdecl)
                        decl = pbody
                    if kind == "swift.init" and "convenience" in pdecl:
                        overriding = False
                    if kind == "swift.init" and self.split_attrs(decl)[1].startswith("init?") and not self.split_attrs(pdecl)[1].startswith("init?"):
                        out.append("%s// SKIPPED (failable init cannot override non-failable): %s" % (indent, decl))
                        return out, "blocked"
                if re.match(r"^(?:@\w+\s+)*static ", decl):
                    out.append("%s// SKIPPED (static member cannot override class member): %s" % (indent, decl))
                    return out, "blocked"
            if overriding:
                prefix += "override "
            if kind == "swift.init" and name in ("init?(coder:)", "init(coder:)"):
                prefix = "public required "
            elif kind == "swift.init" and key in ctx.get("required_init_keys", set()):
                prefix = "public required " + ("override " if overriding else "")
            if kind == "swift.init" and ctx.get("convenience_inits") and not decl.startswith("convenience "):
                decl = "convenience " + decl

        if kind == "swift.enum.case":
            rv = self.raw_value_for(path)
            if not rv and raw_type and raw_type in ("Int", "UInt", "Int32", "UInt32", "Int64", "UInt64", "Int8", "UInt8", "Int16", "UInt16"):
                # Not probed (newer than the probe OS): take the next free value and say so.
                used = ctx.setdefault("used_raw_values", set())
                nxt = ctx.setdefault("next_free_raw", None)
                if nxt is None:
                    nums = [int(v) for v in used if re.match(r"^-?\d+$", v)]
                    sibling_vals = []
                    for mid in self.inv.members.get(ctx.get("owner_pid", ""), []):
                        m2 = self.inv.sym(mid)
                        if m2 and m2["kind"]["identifier"] == "swift.enum.case":
                            r2 = self.raw_value_for(tuple(m2["pathComponents"]))
                            if r2 and re.match(r"^-?\d+$", r2[1]):
                                sibling_vals.append(int(r2[1]))
                    nxt = max(nums + sibling_vals + [-1]) + 1
                ctx["next_free_raw"] = nxt + 1
                used.add(str(nxt))
                out.append("%scase %s = %d // APIGEN: raw value unverified (symbol newer than the probe OS)" % (indent, decl[len("case "):], nxt))
                return out, "emitted"
            if rv and raw_type:
                used = ctx.setdefault("used_raw_values", set())
                if rv[1] in used:
                    # The SDK aliases this case to an earlier one; Swift needs a static alias.
                    out.append("%spublic static var %s: Self { Self(rawValue: %s)! }" % (indent, decl[len("case "):], self.swift_literal(*rv)))
                    return out, "emitted"
                used.add(rv[1])
                out.append("%scase %s = %s" % (indent, decl[len("case "):], self.swift_literal(*rv)))
            else:
                out.append("%s%s" % (indent, decl))
            return out, "emitted"

        if kind in ("swift.property", "swift.type.property", "swift.var"):
            if raw_type and name == "rawValue":
                return None, "synthesized by generator"
            m = re.match(r"^(.*?)\b(var|let) ([^:]+): (.+?)(?: \{ get(?: set)? \})?$", decl)
            if not m:
                out.append("%s// APIGEN could not parse property: %s" % (indent, decl))
                return out, "unparsed"
            attrs, kw, pname, ptype = m.group(1), m.group(2), m.group(3), m.group(4)
            settable = decl.endswith("{ get set }")
            if owner_kind == "protocol" and not optional:
                out.append("%s%s%s" % (indent, attrs, "var %s: %s { get%s }" % (pname, ptype, " set" if settable else "")))
                return out, "emitted"
            if owner_kind == "protocol" and optional:
                dflt = "nil" if ptype.strip().endswith("?") else ("false" if ptype.strip() == "Bool" else None)
                if settable:
                    body = ("{ get { %s } set { } }" % dflt) if dflt else "{ get { unimplementedOptionalRequirement() } set { } }"
                else:
                    body = ("{ %s }" % dflt) if dflt else "{ unimplementedOptionalRequirement() }"
                out.append("%s%spublic var %s: %s %s" % (indent, attrs, pname, ptype, body))
                return out, "emitted"
            head = "%s%s%svar %s: %s" % (indent, attrs, prefix, pname, ptype)
            is_global = kind == "swift.var" and len(path) == 1
            rv = self.raw_value_for(path) if (is_static or is_global) else None
            if rv and is_global:
                # A global constant with a probed value (NSOutlineViewDropOnItemIndex).
                out.append("%s { %s }" % (head, self.swift_literal(*rv)))
                return out, "emitted"
            if rv:
                ptype_clean = ptype.strip()
                if ptype_clean.endswith("!"):
                    ptype_clean = ptype_clean[:-1]
                if ptype_clean.endswith("?"):
                    ptype_clean = ptype_clean[:-1]
                lit = self.swift_literal(*rv)
                init_expr = "%s(rawValue: %s)" % (ptype_clean, lit)
                if self.inv.by_path.get(tuple(ptype_clean.split("."))) and \
                        self.inv.by_path[tuple(ptype_clean.split("."))][0]["kind"]["identifier"] == "swift.enum":
                    init_expr += "!"
                out.append("%s { %s }" % (head, init_expr))
                return out, "emitted"
            if settable:
                out.append("%s {" % head)
                out.append("%s    get { unimplemented() }" % indent)
                out.append("%s    set { unimplemented() }" % indent)
                out.append("%s}" % indent)
            else:
                out.append("%s { unimplemented() }" % head)
            return out, "emitted"

        if kind == "swift.subscript":
            settable = decl.endswith("{ get set }")
            head = re.sub(r" \{ get(?: set)? \}$", "", decl)
            if owner_kind == "protocol" and not optional:
                out.append("%s%s" % (indent, decl))
                return out, "emitted"
            sattrs, head = self.split_attrs(head)
            if settable:
                out.append("%s%s%s%s {" % (indent, sattrs, prefix, head))
                out.append("%s    get { unimplemented() }" % indent)
                out.append("%s    set { unimplemented() }" % indent)
                out.append("%s}" % indent)
            else:
                out.append("%s%s%s%s { unimplemented() }" % (indent, sattrs, prefix, head))
            return out, "emitted"

        if kind in ("swift.method", "swift.type.method", "swift.func", "swift.func.op", "swift.init"):
            if raw_type and kind == "swift.init" and name in ("init(rawValue:)", "init(_:)"):
                return None, "synthesized by generator"
            if owner_kind == "protocol" and not optional:
                out.append("%s%s" % (indent, decl))
                return out, "emitted"
            if owner_kind == "protocol" and optional:
                custom = self.config.get("optionalDefaults", {}).get(".".join(path))
                body = ("{ %s }" % custom) if custom else self.default_body(decl)
                attrs, decl = self.split_attrs(decl)
                out.append("%s%s%s%s %s" % (indent, attrs, "public ", decl, body))
                return out, "emitted"
            attrs, decl = self.split_attrs(decl)
            if kind == "swift.init":
                prefix = prefix.replace("open ", "public ")
            out.append("%s%s%s%s { unimplemented() }" % (indent, attrs, prefix, decl))
            return out, "emitted"

        if kind == "swift.associatedtype":
            out.append("%s%s" % (indent, decl))
            return out, "emitted"

        if kind == "swift.typealias":
            if raw_type and name == "RawValue":
                return None, "synthesized by generator"
            out.append("%s%s%s" % (indent, "public " if owner_kind != "protocol" else "", decl))
            return out, "emitted"

        return None, "unsupported kind %s" % kind

    def is_override_compatible(self, child, parent):
        """Swift override rules, approximately: parameter types equal up to optionality,
        return type equal or covariant (child non-optional where parent is optional)."""
        cp, cr = self.sig_parts(child)
        pp, pr = self.sig_parts(parent)
        if cp != pp:
            return False
        if cr == pr:
            return True
        return pr == cr + "?" or pr == cr + "!"

    def sig_parts(self, decl):
        d = re.sub(r"\s*\{ get(?: set)? \}$", "", decl)
        d = self.normalized_signature(d, strict=True)
        m = RETURN_RE.search(d)
        ret = m.group(1).strip() if m else ""
        params = d[:m.start() + 1] if m else d
        params = params.replace("?", "").replace("!", "")
        return params, ret

    @staticmethod
    def strip_defaults(decl):
        return re.sub(r"\s*=\s*(?:\[\]|\[:\]|nil|true|false|[-\w.]+)(?=[,)])", "", decl)

    @staticmethod
    def split_attrs(decl):
        m = re.match(r"^((?:@\w+(?:\([^)]*\))?\s+)*)(.*)$", decl)
        return (m.group(1), m.group(2)) if m else ("", decl)

    def default_body(self, decl):
        m = RETURN_RE.search(decl)
        if not m:
            return "{ }"
        ret = m.group(1).strip()
        if ret.endswith("?") or ret.endswith("!"):
            return "{ return nil }"
        if ret == "Bool":
            return "{ return false }"
        return "{ unimplementedOptionalRequirement() }"

    # ---------- types ----------
    def type_kind(self, sym):
        return sym["kind"]["identifier"].split(".")[-1]

    def raw_type_of(self, sym):
        """For enums / option sets / newtype structs: the RawValue type, or None."""
        pid = sym["identifier"]["precise"]
        if "s:SY" not in self.inv.conformances.get(pid, []) and "s:s9OptionSetP" not in self.inv.conformances.get(pid, []):
            return None
        for mid in self.inv.members.get(pid, []):
            m = self.inv.sym(mid)
            if m and m["pathComponents"][-1] == "rawValue":
                t = self.decl_text(m)
                mm = re.match(r"^.*?var rawValue: (.+?)(?: \{ get \})?$", t)
                if mm:
                    rt = mm.group(1)
                    if rt.endswith(".RawValue"):
                        for mid2 in self.inv.members.get(pid, []):
                            m2 = self.inv.sym(mid2)
                            if m2 and m2["kind"]["identifier"] == "swift.typealias" and m2["pathComponents"][-1] == "RawValue":
                                t2 = self.decl_text(m2)
                                rt = t2.split("=", 1)[1].strip()
                    return rt
        for mid in self.inv.members.get(pid, []):
            m = self.inv.sym(mid)
            if m and m["pathComponents"][-1] == "init(rawValue:)":
                mm = re.search(r"init\(rawValue: (.+?)\)$", self.decl_text(m))
                if mm:
                    return mm.group(1)
        if sym["kind"]["identifier"] == "swift.enum":
            return "Int"
        return None

    def conformance_list(self, sym):
        pid = sym["identifier"]["precise"]
        kind = self.type_kind(sym)
        confs = self.inv.conformances.get(pid, [])
        names = []
        inherited = set()
        if kind == "class":
            sup = self.inv.superclass.get(pid)
            inherited |= NSOBJECT_CONFORMANCES
            depth = 0
            while sup and depth < 20:
                inherited |= set(self.inv.conformances.get(sup, []))
                sup = self.inv.superclass.get(sup)
                depth += 1
        for c in confs:
            if c in inherited:
                continue
            if c in STDLIB_PROTOCOLS:
                if kind == "class":
                    continue
                if c in ("s:SY",):
                    continue   # handled with raw type
                if c in STRUCT_KEEP_CONFORMANCES or c == "s:s9OptionSetP":
                    names.append(STDLIB_PROTOCOLS[c])
                continue
            if c in FOUNDATION_PROTOCOLS:
                n = FOUNDATION_PROTOCOLS[c]
                if n == "NSObjectProtocol" and kind == "class":
                    continue
                names.append(n)
                continue
            kt = self.inv.known_types.get(c)
            if kt and kt[0] == self.inv.module:
                top = kt[1][0]
                if top in self.pending or top in self.skip_types:
                    continue
                names.append(".".join(kt[1]))
        # dedupe, keep order
        seen, res = set(), []
        for n in names:
            if n not in seen:
                seen.add(n)
                res.append(n)
        return res

    def synthesize_requirements(self, sym, confs, ctx, inner, emitted_sigs, stats):
        """Emit stubs for protocol requirements the SDK class does not list as members
        (ObjC classes implement protocol methods without redeclaring them)."""
        pid = sym["identifier"]["precise"]
        have_map = {k: list(v) for k, v in self.ancestor_keys(pid).items()}
        for k, v in self.own_keys(pid, include_requirements=False).items():
            have_map[k] = list(v) + have_map.get(k, [])
        have = set(have_map)
        base_names = {k[1] for k in have if k[0] == "property"}
        out = []
        for c in self.inv.conformances.get(pid, []):
            reqs = self.protocol_requirements(c) + self.ambiguous_defaults(pid, c)
            for rsym in reqs:
                key = self.member_key(rsym)
                if key and key[0] == "method" and key[1].endswith("()") and key[1][:-2] in base_names and key not in have:
                    out.append("%s// SKIPPED (requirement %s clashes with a property of the same name): %s" % (inner, key[1], self.decl_text(rsym)))
                    continue
                key = self.member_key(rsym)
                if key is None:
                    continue
                if key in have:
                    existing = [x for x in have_map.get(key, []) if x is not None]
                    if not existing or rsym["kind"]["identifier"] in ("swift.init", "swift.property", "swift.type.property") or any(
                            self.normalized_signature(self.decl_text(x), strict=True) == self.normalized_signature(self.decl_text(rsym), strict=True)
                            for x in existing):
                        continue
                    out.append("%s// Requirement of %s (signature differs from the inherited member)" % (inner, ".".join(rsym["pathComponents"][:-1])))
                    have.discard(key)
                rctx = dict(ctx)
                rctx["kind"] = "class"
                r, status = self.emit_member(rsym, rctx, inner)
                if r and status == "emitted":
                    # requirement text comes from the protocol: make it a class member
                    fixed = []
                    for ln in r:
                        fixed.append(ln)
                    out.append("%s// Requirement of %s" % (inner, ".".join(rsym["pathComponents"][:-1])))
                    out += fixed
                    have.add(key)
                    stats["synthesized-requirement"] += 1
                elif r:
                    out += r
        return out

    def ambiguous_defaults(self, class_pid, proto_pid):
        """Requirements of defaulted protocol `proto_pid` that another defaulted protocol the class
        conforms to also declares: Swift cannot pick between two extension defaults, so the
        class gets its own stub."""
        defaulted = self.config.get("defaultedProtocols", [])
        kt = self.inv.known_types.get(proto_pid)
        if not kt or kt[1][0] not in defaulted:
            return []
        others = [c for c in self.all_conformances(class_pid)
                  if c != proto_pid and (self.inv.known_types.get(c) or ("", ("",)))[1][0] in defaulted]
        other_keys = set()
        for o in others:
            for mid in self.inv.members.get(o, []):
                m = self.inv.sym(mid)
                if m:
                    k = self.member_key(m)
                    if k:
                        other_keys.add(k)
        res = []
        for mid in self.inv.members.get(proto_pid, []):
            m = self.inv.sym(mid)
            if m and m["kind"]["identifier"] not in ("swift.init", "swift.associatedtype") and self.member_key(m) in other_keys:
                res.append(m)
        return res

    FOUNDATION_REQUIREMENTS = {
        "c:objc(pl)NSCoding": [("swift.method", "encode(with:)", "func encode(with coder: NSCoder)"),
                               ("swift.init", "init?(coder:)", "init?(coder: NSCoder)")],
        "c:objc(pl)NSSecureCoding": [("swift.type.property", "supportsSecureCoding", "class var supportsSecureCoding: Bool { get }")],
        "c:objc(pl)NSCopying": [("swift.method", "copy(with:)", "func copy(with zone: NSZone? = nil) -> Any")],
        "c:objc(pl)NSMutableCopying": [("swift.method", "mutableCopy(with:)", "func mutableCopy(with zone: NSZone? = nil) -> Any")],
    }

    def protocol_requirements(self, proto_pid):
        """Non-optional requirements of a protocol (and its parents) as pseudo-symbols."""
        res = []
        seen = set()
        stack = [proto_pid]
        while stack:
            p = stack.pop()
            if p in seen:
                continue
            seen.add(p)
            kt = self.inv.known_types.get(p)
            if kt and kt[1][0] in self.config.get("defaultedProtocols", []):
                for mid in self.inv.members.get(p, []):
                    m = self.inv.sym(mid)
                    if m and m["kind"]["identifier"] == "swift.init" and mid not in self.inv.optional_req:
                        res.append(m)
                for parent in self.inv.conformances.get(p, []):
                    stack.append(parent)
                continue
            if p in self.FOUNDATION_REQUIREMENTS:
                for kind, name, decl in self.FOUNDATION_REQUIREMENTS[p]:
                    res.append({"kind": {"identifier": kind}, "identifier": {"precise": "synth:" + p + name},
                                "pathComponents": [FOUNDATION_PROTOCOLS[p], name],
                                "declarationFragments": [{"kind": "text", "spelling": decl}],
                                "accessLevel": "public"})
                for parent in self.inv.conformances.get(p, []):
                    stack.append(parent)
                continue
            psym = self.inv.sym(p)
            if psym is None or psym["kind"]["identifier"] != "swift.protocol":
                continue
            for mid in self.inv.members.get(p, []):
                m = self.inv.sym(mid)
                if not m or mid in self.inv.optional_req:
                    continue
                if m["kind"]["identifier"] in ("swift.class", "swift.struct", "swift.enum", "swift.typealias", "swift.associatedtype"):
                    continue
                res.append(m)
            for parent in self.inv.conformances.get(p, []):
                stack.append(parent)
        return res

    def superclass_name(self, sym):
        override = self.config.get("superclassOverride", {}).get(sym["pathComponents"][0])
        if override:
            return override
        sup = self.inv.superclass.get(sym["identifier"]["precise"])
        if not sup:
            return None
        kt = self.inv.known_types.get(sup)
        if kt:
            return ".".join(kt[1])
        if sup == "c:objc(cs)NSObject":
            return "NSObject"
        return None

    def emit_type(self, sym, indent, as_extension_of=None, parent_sym=None):
        """Emit a type declaration (class/struct/enum/protocol/typealias) with members and
        nested types. Returns (lines, stats)."""
        pid = sym["identifier"]["precise"]
        path = tuple(sym["pathComponents"])
        name = path[-1]
        kind = self.type_kind(sym)
        stats = collections.Counter()
        lines = []
        if kind == "typealias":
            blockers = self.member_blockers(sym)
            if blockers or " some " in self.decl_text(sym):
                lines.append("%s// SKIPPED (%s): %s" % (indent, "; ".join(blockers) or "opaque type", self.decl_text(sym)))
                stats["blocked"] += 1
                return lines, stats
            lines += self.doc_lines(sym, indent)
            lines.append("%spublic %s" % (indent, self.decl_text(sym)))
            stats["emitted"] += 1
            return lines, stats

        access = sym.get("accessLevel", "public")
        decl = self.decl_text(sym)
        decl = re.sub(r"\b(class|struct|enum|protocol) ", "", decl, count=1)
        # decl is now "<attrs> Name<Generics>"
        final = kind == "class" and (" final " in (" " + frag_text(sym["declarationFragments"]) + " "))
        raw_type = self.raw_type_of(sym)
        confs = self.conformance_list(sym)
        is_optionset = "s:s9OptionSetP" in self.inv.conformances.get(pid, [])
        inherit = []
        if kind == "class":
            sup = self.superclass_name(sym)
            if sup:
                inherit.append(sup)
        if kind == "enum" and raw_type:
            inherit.append(raw_type)
        if kind == "protocol":
            for c in self.inv.conformances.get(pid, []):
                if c in FOUNDATION_PROTOCOLS:
                    inherit.append(FOUNDATION_PROTOCOLS[c])
                elif c in STDLIB_PROTOCOLS and c in ("s:SQ", "s:SH", "s:s8SendableP"):
                    inherit.append(STDLIB_PROTOCOLS[c])
                else:
                    kt = self.inv.known_types.get(c)
                    if kt and kt[0] == self.inv.module and kt[1][0] not in self.pending and kt[1][0] not in self.skip_types:
                        inherit.append(".".join(kt[1]))
            # Class-bound ObjC protocols
            if "c:objc(pl)NSObject" in self.inv.conformances.get(pid, []) and "NSObjectProtocol" not in inherit:
                inherit.append("NSObjectProtocol")
            # Swift cannot redeclare an inherited property with another type, so a subclass
            # whose delegate or data source protocol differs from its superclass's (NSOutlineView)
            # keeps the inherited property; the config lists the superclass protocol as an extra
            # parent so `outlineView.dataSource = self` still compiles.
            for extra in self.config.get("protocolExtraParents", {}).get(".".join(path), []):
                if extra not in inherit:
                    inherit.insert(0, extra)
        else:
            inherit += confs
        if kind == "class" and len(path) > 1:
            inherit = [i for i in inherit if i not in ("NSCoding", "NSSecureCoding")]
        if kind == "struct" and raw_type and not is_optionset and "RawRepresentable" not in inherit:
            inherit.insert(0, "RawRepresentable")
        if kind == "struct" and raw_type and "Hashable" not in inherit and "Equatable" not in inherit:
            inherit.append("Hashable")
        if kind == "enum" and raw_type and "Sendable" not in inherit:
            inherit.append("Sendable")

        head_kw = {"class": (access if access == "open" else "public") + " class",
                   "struct": "public struct", "enum": "public enum",
                   "protocol": "public protocol"}[kind]
        if final:
            head_kw = "public final class"
        attrs = ""
        m = re.match(r"^((?:@\w+\s+)*)(.*)$", decl)
        if m:
            attrs, decl = m.group(1), m.group(2)
        where = ""
        wm = re.search(r"\swhere\s.*$", decl)
        if wm:
            where = wm.group(0)
            decl = decl[:wm.start()]
        # fragments of protocols/classes include the inheritance clause; we compute our own
        decl = re.sub(r"\s*:\s.*$", "", decl)
        if kind == "protocol":
            decl = re.sub(r"<[^>]+>", "", decl)
        head = "%s%s%s %s" % (indent, attrs, head_kw, decl)
        if inherit:
            head += ": " + ", ".join(inherit)
        head += where
        lines += self.doc_lines(sym, indent)
        lines.append(head + " {")
        inner = indent + "    "
        member_access = access if kind == "class" else "public"

        if kind == "protocol":
            gm = re.search(r"<([^>]+)>", decl)
            if gm:
                for at in gm.group(1).split(","):
                    lines.append("%sassociatedtype %s" % (inner, at.strip()))
        if "@propertyWrapper" in attrs:
            names = [m2["pathComponents"][-1] for m2 in (self.inv.sym(x) for x in self.inv.members.get(pid, [])) if m2]
            if "wrappedValue" not in names:
                gp = re.search(r"<(\w+)", decl)
                vt = gp.group(1) if gp else "Any"
                lines.append("%s// wrappedValue is unavailable in the SDK (enclosing-instance subscript wrapper); declared for the wrapper to be valid." % inner)
                lines.append("%s@available(*, unavailable) public var wrappedValue: %s { get { unimplemented() } set { unimplemented() } }" % (inner, vt))
        if raw_type and ("Comparable" in inherit) and kind != "enum":
            lines.append("%spublic static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }" % inner)
        if raw_type and kind != "enum":
            lines.append("%spublic let rawValue: %s" % (inner, raw_type))
            lines.append("%spublic init(rawValue: %s) { self.rawValue = rawValue }" % (inner, raw_type))
            if not is_optionset:
                lines.append("%spublic init(_ rawValue: %s) { self.rawValue = rawValue }" % (inner, raw_type))
            lines.append("")

        required_init_keys = set()
        if kind == "class":
            for c in self.inv.conformances.get(pid, []):
                for rsym in self.protocol_requirements(c):
                    if rsym["kind"]["identifier"] == "swift.init":
                        required_init_keys.add(self.member_key(rsym))
        ctx = {"kind": kind, "access": member_access, "owner_path": path, "owner_pid": pid, "raw_type": raw_type,
               "required_init_keys": required_init_keys,
               "final": final, "ancestor_keys": self.ancestor_keys(pid) if kind == "class" else set()}
        nested_types = []
        protocol_defaults = []
        members = [self.inv.sym(mid) for mid in self.inv.members.get(pid, [])]
        members = [m for m in members if m]
        members.sort(key=lambda s: (s["kind"]["identifier"] != "swift.enum.case",
                                    s["kind"]["identifier"] not in ("swift.init",),
                                    s["pathComponents"][-1]))
        emitted_sigs = set()
        defaulted = kind == "protocol" and name in self.config.get("defaultedProtocols", [])
        if defaulted:
            ctx["force_optional"] = True
        for m in members:
            mk = m["kind"]["identifier"]
            if mk in ("swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                nested_types.append(m)
                continue
            if defaulted and mk not in ("swift.associatedtype", "swift.init"):
                protocol_defaults.append(m)
                continue
            mid = m["identifier"]["precise"]
            if kind == "protocol" and mid not in self.inv.required_by and mid not in self.inv.optional_req \
                    and mk not in ("swift.associatedtype",):
                # Declared in a protocol extension by Apple's Swift overlay: a default, not a requirement.
                self._extension_members.add(mid)
                protocol_defaults.append(m)
                continue
            if m.get("swiftExtension", {}).get("constraints"):
                stats["constrained-ext-skipped"] += 1
                if not m["identifier"]["precise"].startswith("s:s"):   # stdlib defaults are synthesized
                    lines.append("%s// SKIPPED (constrained extension): %s" % (inner, self.decl_text(m)))
                continue
            if kind == "protocol" and self.is_optional_requirement(m):
                protocol_defaults.append(m)
                continue
            out, status = self.emit_member(m, ctx, inner)
            stats[status] += 1
            if out:
                sig = out[-1] if status != "emitted" else out[0]
                if status == "emitted":
                    key = re.sub(r"\s*\{.*$", "", out[0]).strip()
                    if key in emitted_sigs:
                        lines.append("%s// DUPLICATE: %s" % (inner, key))
                        stats["duplicate"] += 1
                        stats["emitted"] -= 1
                        continue
                    emitted_sigs.add(key)
                lines += self.doc_lines(m, inner, sym) if status == "emitted" else []
                lines += out
        if kind == "class":
            lines += self.synthesize_requirements(sym, confs, ctx, inner, emitted_sigs, stats)
            has_designated = any(re.match(r"^\s*(?:@\w+\s+)*(?:public|open) (?:required )?(?:override )?init", l) and "convenience" not in l for l in lines)
            own = self.own_keys(pid, include_requirements=False)
            anc = ctx["ancestor_keys"]
            if has_designated and ("init", "init(coder:)") in anc and ("init", "init(coder:)") not in own:
                parent = (anc[("init", "init(coder:)")] or [None])[0]
                pdecl = self.decl_text(parent) if parent is not None else "init?(coder: NSCoder)"
                pattrs, pdecl = self.split_attrs(pdecl)
                lines.append("%s// Required by the superclass (NSCoding)." % inner)
                lines.append("%s%spublic required %s { unimplemented() }" % (inner, pattrs, pdecl))
        if kind == "protocol" and protocol_defaults:
            lines.append("}")
            lines.append("")
            lines.append("%s// Optional requirements (ObjC `@optional`), modelled as defaulted requirements." % indent)
            lines += self.availability_line(sym, indent) or (self.availability_line(parent_sym, indent) if parent_sym else [])
            lines.append("%sextension %s {" % (indent, ".".join(path)))
            for m in protocol_defaults:
                out, status = self.emit_member(m, ctx, inner)
                stats[status] += 1
                if out:
                    lines += self.doc_lines(m, inner, sym) if status == "emitted" else []
                    lines += out
            # requirement declarations must also exist on the protocol itself
            lines.append("}")
            # Re-open the protocol to declare the optional requirements as requirements.
            lines.append("")
        else:
            lines.append(indent + "}")

        # Optional protocol requirements need to be requirements too, so re-emit them
        # as a second protocol block is not possible; instead we insert them before the
        # closing brace of the protocol. Do that by patching lines.
        if kind == "protocol" and protocol_defaults:
            # find first "}" after head
            idx = lines.index("}")  # closing brace of protocol block (emitted at indent 0)
            req_lines = []
            for m in protocol_defaults:
                if self.unavailable(m) or self.member_blockers(m) or "::SYNTHESIZED::" in m["identifier"]["precise"]:
                    continue
                if m["identifier"]["precise"] in self._extension_members:
                    continue
                d = self.strip_defaults(self.decl_text(m))
                req_lines += self.availability_line(m, inner)
                req_lines.append("%s%s" % (inner, d))
            lines[idx:idx] = req_lines

        # Nested types are emitted at file scope as extensions of the parent so that
        # hand-written parents do not have to carry them (and nesting depth is unbounded).
        for nt in nested_types:
            if ".".join(nt["pathComponents"]) in self.skip_members:
                continue
            stats["nested"] += 1
            nl, ns = self.emit_type(nt, "", parent_sym=sym)
            lines.append("")
            lines += self.availability_line(nt, "") or self.availability_line(sym, "") or (self.availability_line(parent_sym, "") if parent_sym else [])
            lines.append("extension %s {" % ".".join(path))
            lines += ["    " + l if l else l for l in nl[:self.first_file_scope_index(nl)]]
            lines.append("}")
            lines += nl[self.first_file_scope_index(nl):]
            stats.update(ns)
        return lines, stats

    @staticmethod
    def first_file_scope_index(nl):
        # nested emit_type output: the type block, then (after a blank line) file-scope extensions
        for i, l in enumerate(nl):
            if l.startswith("extension ") or l.startswith("// Optional requirements"):
                if i > 0 and nl[i - 1].startswith("@available"):
                    return i - 1
                return i
        return len(nl)

    def all_conformances(self, class_pid):
        res = []
        p = class_pid
        depth = 0
        while p and depth < 20:
            res += self.inv.conformances.get(p, [])
            p = self.inv.superclass.get(p)
            depth += 1
        return res

    # ---------- probe ----------
    def collect_probe_entries(self):
        entries = []
        for pid, s in self.inv.symbols.items():
            k = s["kind"]["identifier"]
            if self.unavailable(s):
                continue
            path = s["pathComponents"]
            if k == "swift.enum.case":
                entries.append(path)
            elif k == "swift.type.property":
                # static constants typed as enum/optionset/newtype structs
                frags = s["declarationFragments"]
                tids = [f for f in frags if f["kind"] == "typeIdentifier"]
                if not tids:
                    continue
                last = tids[-1]
                tp = last.get("preciseIdentifier", "")
                kt = self.inv.known_types.get(tp)
                is_value_type = tp.startswith("c:@E@") or tp.startswith("c:@T@") or \
                    (kt is not None and kt[0] in (self.inv.module, "Foundation") and tp.startswith("s:") and
                     any(x["kind"]["identifier"] in ("swift.struct", "swift.enum")
                         for x in self.inv.by_path.get(kt[1], [])))
                if is_value_type and " class " not in " " + frag_text(frags) + " ":
                    entries.append(path)
                elif is_value_type:
                    entries.append(path)
        for pid, s in self.inv.foreign_ext.items():
            k = s["kind"]["identifier"]
            if k == "swift.type.property" and not self.unavailable(s):
                frags = s["declarationFragments"]
                tids = [f for f in frags if f["kind"] == "typeIdentifier"]
                if tids and (tids[-1].get("preciseIdentifier", "").startswith("c:@T@")):
                    entries.append(s["pathComponents"])
        # keep the symbol so availability can be emitted
        by_path = {}
        for pth in entries:
            key = ".".join(pth)
            if key not in by_path:
                by_path[key] = self.inv.by_path.get(tuple(pth), [None])[0] or next(
                    (x for x in self.inv.foreign_ext.values() if x["pathComponents"] == list(pth)), None)
        return sorted(by_path.items())

    def write_probe(self, out_path):
        entries = self.collect_probe_entries()
        lines = ["// Generated by tools/apigen/apigen.py --emit-probe. Compile against the real SDK on macOS.",
                 "import AppKit", "import Foundation", "",
                 "func rv<T: RawRepresentable>(_ v: T) -> String { \"\\(type(of: v.rawValue))|\\(v.rawValue)\" }",
                 "func rv(_ v: Any) -> String { \"?\" }",
                 "nonisolated(unsafe) var results: [String: String] = [:]",
                 ""]
        chunk = 150
        funcs = []
        for i in range(0, len(entries), chunk):
            fname = "probe%d" % (i // chunk)
            funcs.append(fname)
            lines.append("@MainActor func %s() {" % fname)
            for e, esym in entries[i:i + chunk]:
                v = self.introduced(esym) if esym else None
                if v and v > (10, 13):
                    lines.append("    if #available(macOS %d.%d, *) { results[%s] = rv(%s) }" % (v[0], v[1], json.dumps(e), e))
                else:
                    lines.append("    results[%s] = rv(%s)" % (json.dumps(e), e))
            lines.append("}")
            lines.append("")
        lines.append("@MainActor func runAll() {")
        for f in funcs:
            lines.append("    %s()" % f)
        lines.append("}")
        lines.append("MainActor.assumeIsolated { runAll() }")
        lines.append("let data = try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted])")
        lines.append("FileHandle.standardOutput.write(data)")
        with open(out_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        print("probe: %d entries -> %s" % (len(entries), out_path))

    # ---------- driver ----------
    def top_level_types(self):
        res = []
        for pid, s in self.inv.symbols.items():
            if len(s["pathComponents"]) == 1 and s["kind"]["identifier"] in (
                    "swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                res.append(s)
        res.sort(key=lambda s: s["pathComponents"][0])
        return res

    def file_header(self, what):
        return ["// %s" % what,
                "// GENERATED by tools/apigen/apigen.py from the macOS SDK symbol graph. DO NOT EDIT.",
                "// Regenerate: python3 tools/apigen/apigen.py",
                "//",
                "// Every member is either implemented (hand-written types only), stubbed with",
                "// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.",
                "",
                "import Foundation",
                "#if canImport(CoreGraphics)", "import CoreGraphics", "#endif",
                "#if canImport(QuartzCore)", "import QuartzCore", "#endif",
                "#if canImport(CoreText)", "import CoreText", "#endif",
                ""]

    def run(self):
        gen_dir = os.path.join(ROOT, "Sources", "AppKit", "Generated")
        pend_dir = os.path.join(ROOT, "Stubs", "Pending", "AppKit")
        seed_dir = os.path.join(ROOT, "Stubs", "Seeds", "AppKit")
        for d in (gen_dir, pend_dir, seed_dir):
            os.makedirs(d, exist_ok=True)
            for f in os.listdir(d):
                if f.endswith(".swift"):
                    os.remove(os.path.join(d, f))
        report = []
        totals = collections.Counter()
        for s in self.top_level_types():
            name = s["pathComponents"][0]
            if name in self.skip_types:
                report.append((name, self.type_kind(s), "skipped", collections.Counter()))
                continue
            lines, stats = self.emit_type(s, "")
            body = "\n".join(lines) + "\n"
            if name in self.handwritten:
                with open(os.path.join(seed_dir, name + ".swift"), "w") as f:
                    f.write("\n".join(self.file_header("Seed for hand-written %s. Copy to Sources/AppKit/Core and implement." % name)) + body)
                # nested types still ship as generated extensions
                nested = self.nested_only(s)
                if nested:
                    with open(os.path.join(gen_dir, name + "+Types.swift"), "w") as f:
                        f.write("\n".join(self.file_header("Nested types of %s" % name)) + nested)
                status = "handwritten"
                stats.update(self.handwritten_stats(name))
            elif name in self.pending:
                with open(os.path.join(pend_dir, name + ".swift"), "w") as f:
                    f.write("\n".join(self.file_header("PENDING: %s (%s)" % (name, self.pending_reason(name)))) + body)
                status = "pending"
            else:
                with open(os.path.join(gen_dir, name + ".swift"), "w") as f:
                    f.write("\n".join(self.file_header(name)) + body)
                status = "generated"
            report.append((name, self.type_kind(s), status, stats))
            totals.update(stats)
        self.write_globals(gen_dir)
        self.write_foreign_extensions(gen_dir)
        self.write_report(report, totals)

    def nested_only(self, sym):
        pid = sym["identifier"]["precise"]
        path = tuple(sym["pathComponents"])
        out = []
        for mid in self.inv.members.get(pid, []):
            m = self.inv.sym(mid)
            if m and m["kind"]["identifier"] in ("swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                # A nested type listed in skipMembers is hand-written next to its parent.
                if ".".join(m["pathComponents"]) in self.skip_members:
                    continue
                nl, _ = self.emit_type(m, "", parent_sym=sym)
                k = self.first_file_scope_index(nl)
                out += self.availability_line(m, "") or self.availability_line(sym, "")
                out.append("extension %s {" % ".".join(path))
                out += ["    " + l if l else l for l in nl[:k]]
                out.append("}")
                out += nl[k:]
                out.append("")
        return "\n".join(out)

    def handwritten_stats(self, name):
        c = collections.Counter()
        core = os.path.join(ROOT, "Sources", "AppKit", "Core")
        for dp, _, fs in os.walk(core):
            for f in fs:
                if f == name + ".swift" or f.startswith(name + "+"):
                    txt = open(os.path.join(dp, f)).read()
                    c["unimplemented-calls"] += txt.count("unimplemented(")
        return c

    def pending_reason(self, name):
        return self.config.get("pendingReasons", {}).get(name, "does not compile yet")

    def write_globals(self, gen_dir):
        lines = self.file_header("Global functions and variables")
        for pid, s in sorted(self.inv.symbols.items(), key=lambda kv: kv[1]["pathComponents"]):
            if len(s["pathComponents"]) != 1:
                continue
            k = s["kind"]["identifier"]
            if k not in ("swift.func", "swift.var"):
                continue
            out, status = self.emit_member(s, {"kind": "extension_struct", "access": "public", "owner_path": ()}, "")
            if out:
                lines += self.doc_lines(s, "") if status == "emitted" else []
                lines += out
                lines.append("")
        with open(os.path.join(gen_dir, "_Globals.swift"), "w") as f:
            f.write("\n".join(lines) + "\n")

    def write_foreign_extensions(self, gen_dir):
        """AppKit's extensions on Foundation/other-module types (AppKit@Foundation graph)."""
        groups = collections.defaultdict(list)
        for pid, s in self.inv.foreign_ext.items():
            if len(s["pathComponents"]) < 2:
                continue
            k = s["kind"]["identifier"]
            ext = s.get("swiftExtension", {})
            if ext.get("constraints"):
                continue
            owner = tuple(s["pathComponents"][:-1])
            if k in ("swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                if len(s["pathComponents"]) == 2:
                    groups[(ext.get("extendedModule", "?"), owner)].append(s)
                continue
            if len(s["pathComponents"]) > 2:
                # Member of a nested type: emitted with that type if AppKit declares it,
                # otherwise (Foundation's own nested type, e.g. NSAttributedString.Key) extended here.
                owner_declared_here = any(x["pathComponents"] == list(owner) and x["kind"]["identifier"] in
                                          ("swift.class", "swift.struct", "swift.enum") for x in self.inv.foreign_ext.values())
                if owner_declared_here:
                    continue
            # Skip members whose owner is itself a nested type we don't have (e.g. AttributeScopes.AppKitAttributes.*)
            groups[(ext.get("extendedModule", "?"), owner)].append(s)
        lines = self.file_header("AppKit extensions on Foundation types")
        skipped = []
        for (mod, owner), syms in sorted(groups.items()):
            top = owner[0]
            if mod != "Foundation" or top not in self.foundation_types or top in ("AttributeScopes", "AttributeDynamicLookup"):
                skipped.append((mod, ".".join(owner), len(syms)))
                continue
            lines.append("extension %s {" % ".".join(owner))
            owner_kind = None
            for s in syms:
                ext = s.get("swiftExtension", {})
                owner_kind = ext.get("typeKind")
                break
            ctx = {"kind": "extension_struct", "access": "public", "owner_path": owner,
                   "convenience_inits": owner_kind == "swift.class"}
            trailing = []
            for s in sorted(syms, key=lambda x: x["pathComponents"][-1]):
                if s["kind"]["identifier"] in ("swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"):
                    nl, _ = self.emit_type(s, "")
                    k = self.first_file_scope_index(nl)
                    lines += ["    " + l if l else l for l in nl[:k]]
                    trailing += nl[k:]
                    continue
                out, status = self.emit_member(s, ctx, "    ")
                if out:
                    lines += self.doc_lines(s, "    ") if status == "emitted" else []
                    lines += out
            lines.append("}")
            lines += trailing
            lines.append("")
        if skipped:
            lines.append("// Extensions not emitted (owner type unavailable on Windows):")
            for mod, owner, n in skipped:
                lines.append("//   %s.%s (%d members)" % (mod, owner, n))
        with open(os.path.join(gen_dir, "Foundation+AppKit.swift"), "w") as f:
            f.write("\n".join(lines) + "\n")

    def write_report(self, report, totals):
        p = os.path.join(ROOT, "docs", "API-COVERAGE.md")
        lines = ["# AppKit API coverage", "",
                 "Generated by `tools/apigen/apigen.py`. Do not edit.", "",
                 "Source SDK: see `api-inventory/SDK-VERSION.txt`.", "",
                 "## Totals", "",
                 "| Metric | Count |", "| --- | ---: |"]
        n_types = len(report)
        by_status = collections.Counter(r[2] for r in report)
        lines.append("| Top-level types in SDK | %d |" % n_types)
        for st in ("handwritten", "generated", "pending", "skipped"):
            lines.append("| Types %s | %d |" % (st, by_status[st]))
        for k in ("emitted", "blocked", "unavailable", "synthesized", "duplicate", "nested",
                  "constrained-ext-skipped", "unparsed", "unimplemented-calls"):
            lines.append("| Members %s | %d |" % (k, totals[k]))
        lines += ["", "Status meanings: **handwritten** lives in `Sources/AppKit/Core` and is the real",
                  "implementation (the `unimplemented-calls` column counts members still stubbed);",
                  "**generated** compiles as a stub; **pending** is generated but excluded from the",
                  "build (see reason); **blocked** members reference a type not yet available on Windows.",
                  "", "## Types", "",
                  "| Type | Kind | Status | Emitted | Blocked | Nested | Still stubbed (handwritten) |",
                  "| --- | --- | --- | ---: | ---: | ---: | ---: |"]
        for name, kind, status, stats in report:
            lines.append("| %s | %s | %s | %d | %d | %d | %s |" % (
                name, kind, status, stats["emitted"], stats["blocked"], stats["nested"],
                stats["unimplemented-calls"] if status == "handwritten" else ""))
        with open(p, "w") as f:
            f.write("\n".join(lines) + "\n")
        print("coverage: %d types (%s); members emitted=%d blocked=%d" % (
            n_types, dict(by_status), totals["emitted"], totals["blocked"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--module", default="AppKit")
    ap.add_argument("--emit-probe", help="write the raw-value probe program and exit")
    args = ap.parse_args()

    inv = Inventory(args.module)
    inv.load_graph(os.path.join(RAW, args.module + ".symbols.json"), foreign=False)
    for f in sorted(os.listdir(RAW)):
        if f.startswith(args.module + "@") and f.endswith(".symbols.json"):
            inv.load_graph(os.path.join(RAW, f), foreign=True)
    for other in ("Foundation", "CoreGraphics", "QuartzCore", "CoreText"):
        p = os.path.join(RAW, other + ".symbols.json")
        if os.path.exists(p):
            inv.load_other_module_types(p)
        for f in sorted(os.listdir(RAW)):
            if f.startswith(other + "@") and f.endswith(".symbols.json"):
                inv.load_other_module_types(os.path.join(RAW, f))

    with open(os.path.join(ROOT, "tools", "apigen", "config.json")) as f:
        config = json.load(f)
    values = {}
    vp = os.path.join(ROOT, "api-inventory", args.module + ".values.json")
    if os.path.exists(vp):
        with open(vp) as f:
            values = json.load(f)
    with open(os.path.join(ROOT, "api-inventory", "Foundation-windows-types.json")) as f:
        foundation_types = json.load(f)

    g = Generator(inv, config, values, foundation_types, args)
    if args.emit_probe:
        g.write_probe(args.emit_probe)
        return
    g.run()


if __name__ == "__main__":
    main()
