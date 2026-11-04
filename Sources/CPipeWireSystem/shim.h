// PipeWire headers (libpipewire-0.3-dev). This target exists for its pkg-config include
// paths, which the CPipeWire shim needs to compile; nothing imports the module itself and
// the shim dlopens the library at runtime, so there is no link dependency.
#include <pipewire/pipewire.h>
