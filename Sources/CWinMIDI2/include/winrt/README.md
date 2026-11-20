# No C++/WinRT projection needed

`cwinmidi2.cpp` no longer uses a C++/WinRT projection of `Windows.Devices.Midi2`. It calls the
API through the raw WinRT ABI in `../midi2abi.h` (interface vtables, IIDs, enums, runtime
class names and the pinterface IIDs of the few `Windows.Foundation` generics it meets), which
is checked in and needs only the Windows SDK to compile. Nothing has to be generated on the
build PC and `cppwinrt.exe` is not used.

Do not put generated `winrt\*.h` headers here: nothing includes them.

To regenerate `midi2abi.h` for a new API version (or to add classes), run
`tools/midi2abi/midi2abi.py` on that version's `Windows.Devices.Midi2.winmd`; see
`tools/midi2abi/README.md` and ADR-0050 ("Windows MIDI Services"). At run time,
`Windows.Devices.Midi2.dll` and `.pri` from the nupkg still go beside the executable until
Windows ships the API in box.

This folder can be deleted once nothing refers to it.
