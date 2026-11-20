# midi2abi

`midi2abi.py` reads `Windows.Devices.Midi2.winmd` (from the `Windows.Devices.Midi2` nupkg,
MIT, attached to microsoft/MIDI's In-box Preview release) and writes
`Sources/CWinMIDI2/include/midi2abi.h`: every interface IID of the namespace, the enums and
structs, raw vtables for the interfaces the CoreMIDI module calls, and the pinterface IIDs of
the parameterized interfaces and delegates those signatures mention. It needs `dnfile`:

```bash
python3 -m venv venv && venv/bin/pip install dnfile
venv/bin/python tools/midi2abi/midi2abi.py Windows.Devices.Midi2.winmd --list
venv/bin/python tools/midi2abi/midi2abi.py Windows.Devices.Midi2.winmd \
  --classes Windows.Devices.Midi2.MidiSession,Windows.Devices.Midi2.MidiEndpointConnection,... \
  > Sources/CWinMIDI2/include/midi2abi.h
```

The current header was generated from 0.99.92-preview.11 with the class list in the
header's `MIDI2ABI_CLASS_NAMES`. The pinterface IID algorithm is checked against
`IVectorView<String>` (`2f13c006-a03a-5f69-b090-75a43e33423e`). See ADR-0050.
