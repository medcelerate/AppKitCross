#!/usr/bin/env python3
"""Generates midi2abi.h, the raw WinRT ABI (IIDs, enums, structs, vtables) of the parts of
Windows.Devices.Midi2 the CoreMIDI module calls, from the API's .winmd, so the Windows
MIDI Services backend compiles on any PC without a C++/WinRT projection (ADR-0050).

    python3 -m venv venv && venv/bin/pip install dnfile
    venv/bin/python tools/midi2abi/midi2abi.py <Windows.Devices.Midi2.winmd> \
        --classes Windows.Devices.Midi2.MidiSession,... > Sources/CWinMIDI2/include/midi2abi.h

The winmd is `ref/native/Windows.Devices.Midi2.winmd` in the `Windows.Devices.Midi2`
nupkg (MIT) attached to microsoft/MIDI's release. Method order in a vtable is the
MethodDef order of the metadata, after IInspectable's six slots; parameterized-interface
IIDs (TypedEventHandler<...>, IVectorView<...>) follow the WinRT pinterface algorithm.
"""
import argparse, hashlib, struct, sys, uuid
import dnfile

ELEMENT = {0x01: 'void', 0x02: 'boolean', 0x03: 'WCHAR', 0x04: 'int8_t', 0x05: 'uint8_t', 0x06: 'int16_t',
           0x07: 'uint16_t', 0x08: 'int32_t', 0x09: 'uint32_t', 0x0a: 'int64_t', 0x0b: 'uint64_t',
           0x0c: 'float', 0x0d: 'double', 0x0e: 'HSTRING', 0x1c: 'IInspectable *'}
SIG = {0x02: 'b1', 0x03: 'c2', 0x04: 'i1', 0x05: 'u1', 0x06: 'i2', 0x07: 'u2', 0x08: 'i4', 0x09: 'u4',
       0x0a: 'i8', 0x0b: 'u8', 0x0c: 'f4', 0x0d: 'f8', 0x0e: 'string', 0x1c: 'cinterface(IInspectable)'}
PINTERFACE_NAMESPACE = uuid.UUID('11f47ad5-7b73-42c0-abae-878b1e16adee')
KNOWN_GENERIC = {  # Windows.Foundation(.Collections) parameterized interfaces and delegates
    'Windows.Foundation.TypedEventHandler`2': '9de1c534-6ae1-11e0-84e1-18a905bcc53f',
    'Windows.Foundation.EventHandler`1': '9de1c534-6ae1-11e0-84e1-18a905bcc53f',  # placeholder, fixed below
    'Windows.Foundation.Collections.IVectorView`1': 'bbe1fa4c-b0e3-4583-baef-1f1b2e483e56',
    'Windows.Foundation.Collections.IVector`1': '913337e9-11a1-4345-a3a2-4e7f956e222d',
    'Windows.Foundation.Collections.IIterable`1': 'faa585ea-6214-4217-afda-7f46de5869b3',
    'Windows.Foundation.Collections.IIterator`1': '6a79e863-4300-459a-9966-cbb660963ee1',
    'Windows.Foundation.Collections.IMapView`2': 'e480ce40-a4fe-4ad6-b0e1-2d4e9b1b1c66',
    'Windows.Foundation.Collections.IMap`2': '3c2925fe-8519-45c1-aa79-197b6718c1c1',
    'Windows.Foundation.Collections.IKeyValuePair`2': '02b51929-c1c4-4a7e-89b4-4b3a2f15a0e4',
    'Windows.Foundation.IReference`1': '61c17706-2d65-11e0-9ae8-d48564015472',
    'Windows.Foundation.IAsyncOperation`1': '9fc2b0bb-e446-44e2-aa61-9cab8f636af2',
    'Windows.Foundation.AsyncOperationCompletedHandler`1': 'fcdcf02c-e5d8-4478-915a-4d90b74b83a5',
}
KNOWN_GENERIC['Windows.Foundation.EventHandler`1'] = '9de1c534-6ae1-11e0-84e1-18a905bcc53f'


def s(x):
    return str(x) if x is not None else ''


def blob(x):
    return bytes(x.value) if hasattr(x, 'value') else bytes(x)


def read_compressed(data, i):
    b0 = data[i]
    if b0 & 0x80 == 0:
        return b0, i + 1
    if b0 & 0xC0 == 0x80:
        return ((b0 & 0x3F) << 8) | data[i + 1], i + 2
    return ((b0 & 0x1F) << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3], i + 4


def guid_from_blob(b):
    # CustomAttribute blob: prolog 01 00, then the GUID's 11 fields as the ctor takes them.
    a, b1, c = struct.unpack_from('<IHH', b, 2)
    rest = b[10:18]
    return uuid.UUID(fields=(a, b1, c, rest[0], rest[1], int.from_bytes(rest[2:8], 'big')))


def guid_c(u):
    f = u.fields
    return '{0x%08x, 0x%04x, 0x%04x, {0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x}}' % (
        f[0], f[1], f[2], f[3], f[4], (f[5] >> 40) & 0xff, (f[5] >> 32) & 0xff, (f[5] >> 24) & 0xff,
        (f[5] >> 16) & 0xff, (f[5] >> 8) & 0xff, f[5] & 0xff)


def pinterface_guid(signature):
    digest = hashlib.sha1(PINTERFACE_NAMESPACE.bytes + signature.encode('utf-8')).digest()[:16]
    raw = bytearray(digest)
    raw[6] = (raw[6] & 0x0F) | 0x50
    raw[8] = (raw[8] & 0x3F) | 0x80
    return uuid.UUID(bytes=bytes(raw))


class Metadata:
    def __init__(self, path):
        self.pe = dnfile.dnPE(path)
        md = self.pe.net.mdtables
        self.md = md
        self.typedefs = {}
        for i, r in enumerate(md.TypeDef.rows):
            self.typedefs[i + 1] = r
        self.typerefs = {i + 1: r for i, r in enumerate(md.TypeRef.rows)}
        self.typespecs = {i + 1: r for i, r in enumerate(md.TypeSpec.rows)}
        # Custom attributes by parent (table, index)
        self.attrs = {}
        for r in md.CustomAttribute.rows:
            key = (r.Parent.table.name, r.Parent.row_index)
            name = self.attr_name(r)
            self.attrs.setdefault(key, []).append((name, blob(r.Value) if r.Value else b''))
        self.impls = {}
        for r in md.InterfaceImpl.rows:
            self.impls.setdefault(r.Class.row_index, []).append(r)
        self.method_index = {}
        for i, r in enumerate(md.MethodDef.rows):
            self.method_index[id(r)] = i + 1
        # Overloads carry the unique ABI name in their OverloadAttribute.
        self.overload_names = {}
        for (table, index), attrs in self.attrs.items():
            if table != 'MethodDef': continue
            for name, data in attrs:
                if name == 'OverloadAttribute' and len(data) > 3:
                    ln, i = read_compressed(data, 2)
                    self.overload_names[index] = data[i:i + ln].decode('utf-8')
        self.by_name = {}
        for idx, r in self.typedefs.items():
            self.by_name[s(r.TypeNamespace) + '.' + s(r.TypeName)] = idx

    def attr_name(self, r):
        t = r.Type.row
        cls = getattr(t, 'Class', None)
        row = cls.row if cls is not None else None
        return s(getattr(row, 'TypeName', '')) if row is not None else ''

    def typedef_attrs(self, idx):
        return self.attrs.get(('TypeDef', idx), [])

    def full_name(self, idx):
        r = self.typedefs[idx]
        return s(r.TypeNamespace) + '.' + s(r.TypeName)

    def coded_type(self, data, i):
        """TypeDefOrRef coded index -> (kind, fullname, typespec blob)"""
        v, i = read_compressed(data, i)
        tag, idx = v & 3, v >> 2
        if tag == 0:
            return ('def', self.full_name(idx), None), i
        if tag == 1:
            r = self.typerefs[idx]
            return ('ref', s(r.TypeNamespace) + '.' + s(r.TypeName), None), i
        return ('spec', None, blob(self.typespecs[idx].Signature)), i

    def parse_type(self, data, i):
        """Returns (ctype, winrt signature string, is_out_byref), next index."""
        et = data[i]; i += 1
        if et in ELEMENT:
            return (ELEMENT[et], SIG.get(et, 'void'), False), i
        if et == 0x10:  # BYREF
            (ct, sig, _), i = self.parse_type(data, i)
            return (ct + ' *', sig, True), i
        if et in (0x11, 0x12):  # VALUETYPE, CLASS
            (kind, name, _), i = self.coded_type(data, i)
            return self.named_type(name, et == 0x11), i
        if et == 0x15:  # GENERICINST
            inner = data[i]; i += 1
            (kind, name, _), i = self.coded_type(data, i)
            n, i = read_compressed(data, i)
            args = []
            for _ in range(n):
                (ct, sig, _), i = self.parse_type(data, i)
                args.append(sig)
            base = KNOWN_GENERIC.get(name)
            if base:
                sig = 'pinterface({%s};%s)' % (base, ';'.join(args))
                self.generics_seen[sig] = (name, args)
            else:
                sig = 'pinterface(?%s;%s)' % (name, ';'.join(args))
            return ('IInspectable * /* %s<%s> */' % (name.split('.')[-1].split('`')[0], ', '.join(a.split(';')[0].split('(')[-1] for a in args)), sig, False), i
        if et == 0x1d:  # SZARRAY
            (ct, sig, _), i = self.parse_type(data, i)
            return ('ARRAY(' + ct + ')', sig, False), i
        if et in (0x13, 0x1e):  # VAR / MVAR
            n, i = read_compressed(data, i)
            return ('IInspectable *', 'T%d' % n, False), i
        if et in (0x1f, 0x20):  # modifiers
            _, i = self.coded_type(data, i)
            return self.parse_type(data, i)
        return ('void * /* et 0x%02x */' % et, '?', False), i

    def named_type(self, name, is_value):
        idx = self.by_name.get(name)
        if idx is not None:
            r = self.typedefs[idx]
            ext = r.Extends.row if r.Extends and r.Extends.row is not None else None
            extname = s(getattr(ext, 'TypeName', ''))
            if extname == 'Enum':
                return ('int32_t /* %s */' % name.split('.')[-1], 'enum(%s;i4)' % name, False)
            if extname == 'ValueType':
                return ('struct %s' % cname(name), self.struct_signature(idx), False)
            if r.Flags.tdInterface:
                iid = self.interface_iid(idx)
                return ('struct %s *' % cname(name), '{%s}' % iid, False)
            if extname == 'MulticastDelegate':
                return ('IUnknown * /* %s */' % name.split('.')[-1], '?delegate', False)
            default = self.default_interface(idx)
            return ('IInspectable * /* %s */' % name.split('.')[-1], 'rc(%s;{%s})' % (name, default), False)
        if name == 'System.Guid':
            return ('GUID', 'g16', False)
        if name == 'Windows.Foundation.EventRegistrationToken':
            return ('EventRegistrationToken', 'struct(Windows.Foundation.EventRegistrationToken;i8)', False)
        if name == 'Windows.Foundation.TimeSpan':
            return ('int64_t /* TimeSpan */', 'struct(Windows.Foundation.TimeSpan;i8)', False)
        if name == 'Windows.Foundation.DateTime':
            return ('int64_t /* DateTime */', 'struct(Windows.Foundation.DateTime;i8)', False)
        if name == 'System.Object':
            return ('IInspectable *', 'cinterface(IInspectable)', False)
        if name == 'Windows.Foundation.Uri':
            return ('IInspectable * /* Uri */', 'rc(Windows.Foundation.Uri;{9e365e57-48b2-4160-956f-c7385120bbfc})', False)
        if name == 'Windows.Devices.Enumeration.DeviceInformation':
            return ('IInspectable * /* DeviceInformation */', 'rc(Windows.Devices.Enumeration.DeviceInformation;{aba0fb95-4398-489d-8e44-e6130927011f})', False)
        if name.startswith('Windows.Devices.Enumeration.DeviceWatcher'):
            return ('IInspectable * /* DeviceWatcher */', 'rc(Windows.Devices.Enumeration.DeviceWatcher;{c9eab97d-8f6b-4f96-a9f4-abc814e22271})', False)
        return ('IInspectable * /* %s */' % name, '?' + name, False)

    def struct_signature(self, idx):
        r = self.typedefs[idx]
        parts = []
        for f in (r.FieldList or []):
            data = blob(f.row.Signature)
            (ct, sig, _), _ = self.parse_type(data, 1)
            parts.append(sig)
        return 'struct(%s;%s)' % (self.full_name(idx), ';'.join(parts))

    def interface_iid(self, idx):
        for name, data in self.typedef_attrs(idx):
            if name == 'GuidAttribute':
                return str(guid_from_blob(data))
        return '00000000-0000-0000-0000-000000000000'

    def default_interface(self, idx):
        for impl in self.impls.get(idx, []):
            key = ('InterfaceImpl', self.md.InterfaceImpl.rows.index(impl) + 1)
            if any(n == 'DefaultAttribute' for n, _ in self.attrs.get(key, [])):
                return self.impl_iid(impl)
        impls = self.impls.get(idx, [])
        return self.impl_iid(impls[0]) if impls else '00000000-0000-0000-0000-000000000000'

    def impl_iid(self, impl):
        t = impl.Interface
        if t.table.name == 'TypeDef':
            return self.interface_iid(t.row_index)
        if t.table.name == 'TypeRef':
            r = t.row
            name = s(r.TypeNamespace) + '.' + s(r.TypeName)
            idx = self.by_name.get(name)
            return self.interface_iid(idx) if idx else '?' + name
        data = blob(self.typespecs[t.row_index].Signature)
        (ct, sig, _), _ = self.parse_type(data, 0)
        return pinterface_guid(sig) if sig.startswith('pinterface({') else '?' + sig

    def methods(self, idx):
        r = self.typedefs[idx]
        out = []
        for m in (r.MethodList or []):
            row = m.row
            data = blob(row.Signature)
            i = 0
            conv = data[i]; i += 1
            if conv & 0x10:
                _, i = read_compressed(data, i)
            n, i = read_compressed(data, i)
            (rct, rsig, _), i = self.parse_type(data, i)
            params = []
            names = [s(p.row.Name) for p in (row.ParamList or [])]
            # Param rows: sequence 0 is the return value's row when present
            seqs = [p.row.Sequence for p in (row.ParamList or [])]
            pnames = [n for n, q in zip(names, seqs) if q != 0]
            for k in range(n):
                (ct, sig, byref), i = self.parse_type(data, i)
                params.append((ct, pnames[k] if k < len(pnames) else 'arg%d' % k, byref))
            abi_name = self.overload_names.get(self.method_index.get(id(row), 0), s(row.Name))
            out.append((abi_name, rct, params))
        return out


def cname(full):
    return full.replace('Windows.Devices.Midi2.', '').replace('Windows.Foundation.', 'WF_').replace('.', '_')


def emit(md, class_names, out):
    md.generics_seen = {}
    want = set()
    for cn in class_names:
        idx = md.by_name.get(cn)
        if idx is None:
            print('warning: no type %s' % cn, file=sys.stderr); continue
        r = md.typedefs[idx]
        if r.Flags.tdInterface:
            want.add(idx); continue
        for impl in md.impls.get(idx, []):
            t = impl.Interface
            if t.table.name == 'TypeDef': want.add(t.row_index)
            elif t.table.name == 'TypeRef':
                j = md.by_name.get(s(t.row.TypeNamespace) + '.' + s(t.row.TypeName))
                if j: want.add(j)
        for name, data in md.typedef_attrs(idx):
            if name in ('StaticAttribute', 'ActivatableAttribute') and len(data) > 3:
                ln, i = read_compressed(data, 2)
                typename = data[i:i + ln].decode('utf-8')
                j = md.by_name.get(typename)
                if j: want.add(j)
    lines = []
    w = lines.append
    w('// midi2abi.h: generated by tools/midi2abi/midi2abi.py from Windows.Devices.Midi2.winmd')
    w('// (Windows.Devices.Midi2 0.99.92-preview.11, MIT). Do not edit; regenerate (ADR-0050).')
    w('// Raw WinRT ABI: an interface is a struct whose first member is its vtable; methods')
    w('// follow IInspectable\'s six slots in metadata order; a method\'s return value is its')
    w('// trailing out parameter; ARRAY(T) is a (uint32_t count, T *data) pair.')
    w('#pragma once')
    w('#if defined(_WIN32)')
    w('#include <windows.h>')
    w('#include <inspectable.h>')
    w('#include <winstring.h>')
    w('#include <eventtoken.h>')
    w('#include <stdint.h>')
    w('')
    w('#define MIDI2ABI_CLASS_NAMES \\')
    classes = [cn for cn in class_names if md.by_name.get(cn) and not md.typedefs[md.by_name[cn]].Flags.tdInterface]
    for cn in classes:
        w('    X(%s, L"%s") \\' % (cname(cn), cn))
    w('')
    # Enums
    w('// Enums (int32_t values)')
    for idx, r in md.typedefs.items():
        name = md.full_name(idx)
        if not name.startswith('Windows.Devices.Midi2'): continue
        ext = r.Extends.row if r.Extends and r.Extends.row is not None else None
        if s(getattr(ext, 'TypeName', '')) != 'Enum': continue
        w('enum %s {' % cname(name))
        for f in (r.FieldList or []):
            fname = s(f.row.Name)
            if fname == 'value__': continue
            value = None
            for c in md.md.Constant.rows:
                if c.Parent.table.name == 'Field' and c.Parent.row is f.row:
                    value = int.from_bytes(blob(c.Value)[:4], 'little', signed=True); break
            w('    %s_%s = %s,' % (cname(name), fname, value))
        w('};')
    w('')
    # Structs
    w('// Structs')
    for idx, r in md.typedefs.items():
        name = md.full_name(idx)
        if not name.startswith('Windows.Devices.Midi2'): continue
        ext = r.Extends.row if r.Extends and r.Extends.row is not None else None
        if s(getattr(ext, 'TypeName', '')) != 'ValueType': continue
        w('struct %s {' % cname(name))
        for f in (r.FieldList or []):
            data = blob(f.row.Signature)
            (ct, sig, _), _ = md.parse_type(data, 1)
            w('    %s %s;' % (ct, s(f.row.Name)))
        w('};')
    w('')
    # IIDs for every interface in the namespace
    w('// Interface IIDs (GuidAttribute of the metadata)')
    for idx, r in md.typedefs.items():
        name = md.full_name(idx)
        if not name.startswith('Windows.Devices.Midi2') or not r.Flags.tdInterface: continue
        w('static const IID IID_%s = %s; // %s' % (cname(name), guid_c(uuid.UUID(md.interface_iid(idx))), name))
    w('')
    # Forward declarations and vtables for the wanted interfaces
    w('// Vtables of the interfaces the module calls')
    for idx in sorted(want):
        w('struct %s;' % cname(md.full_name(idx)))
    w('')
    for idx in sorted(want):
        name = md.full_name(idx)
        cn = cname(name)
        w('// %s {%s}' % (name, md.interface_iid(idx)))
        w('struct %sVtbl {' % cn)
        w('    HRESULT (STDMETHODCALLTYPE *QueryInterface)(struct %s *self, REFIID riid, void **object);' % cn)
        w('    ULONG (STDMETHODCALLTYPE *AddRef)(struct %s *self);' % cn)
        w('    ULONG (STDMETHODCALLTYPE *Release)(struct %s *self);' % cn)
        w('    HRESULT (STDMETHODCALLTYPE *GetIids)(struct %s *self, ULONG *count, IID **iids);' % cn)
        w('    HRESULT (STDMETHODCALLTYPE *GetRuntimeClassName)(struct %s *self, HSTRING *name);' % cn)
        w('    HRESULT (STDMETHODCALLTYPE *GetTrustLevel)(struct %s *self, TrustLevel *level);' % cn)
        for mname, rct, params in md.methods(idx):
            args = ['struct %s *self' % cn]
            for ct, pname, byref in params:
                if ct.startswith('ARRAY('):
                    inner = ct[6:-1]
                    args.append('uint32_t %sLength, %s *%s' % (pname, inner, pname))
                else:
                    args.append('%s %s' % (ct, pname))
            if rct != 'void':
                if rct.startswith('ARRAY('):
                    args.append('uint32_t *resultLength, %s **result' % rct[6:-1])
                else:
                    args.append('%s *result' % rct)
            w('    HRESULT (STDMETHODCALLTYPE *%s)(%s);' % (mname, ', '.join(args)))
        w('};')
        w('struct %s { const struct %sVtbl *lpVtbl; };' % (cn, cn))
        w('')
    # Parameterized interface IIDs encountered
    w('// Parameterized interfaces and delegates met in those signatures (WinRT pinterface IIDs,')
    w('// SHA-1 of the signature under the pinterface namespace; verify one against a projection')
    w('// when possible)')
    for sig, (gname, args) in sorted(md.generics_seen.items()):
        g = pinterface_guid(sig)
        w('// %s' % sig)
        w('static const IID IID_%s_%s = %s;' % (cname(gname.split('`')[0]), '_'.join(a.split(';')[0].split('(')[-1].split('.')[-1].strip('{})') for a in args).replace('-', ''), guid_c(g)))
    w('#endif')
    out.write('\n'.join(lines) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('winmd')
    ap.add_argument('--classes', default='', help='comma-separated runtime class or interface full names')
    ap.add_argument('--list', action='store_true', help='list every type in the namespace and exit')
    a = ap.parse_args()
    md = Metadata(a.winmd)
    if a.list:
        for idx, r in md.typedefs.items():
            name = md.full_name(idx)
            if name.startswith('Windows.Devices.Midi2'):
                kind = 'interface' if r.Flags.tdInterface else s(getattr(r.Extends.row, 'TypeName', 'class') if r.Extends and r.Extends.row is not None else 'class')
                print(kind, name)
        return
    emit(md, [c for c in a.classes.split(',') if c], sys.stdout)


if __name__ == '__main__':
    main()
