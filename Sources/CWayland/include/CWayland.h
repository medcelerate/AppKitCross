// Wayland client, wl_cursor themes, xkbcommon and the xdg-shell protocol for the Linux
// Wayland window backend (Milestone 8).
//
// The protocol headers and the `protocols/*.c` interface tables are wayland-scanner
// output checked in so that SwiftPM needs no build step; regenerate them with
// `tools/linux/gen-wayland-protocols.sh` when wayland-protocols moves.
#ifndef APPKITWIN_CWAYLAND_H
#define APPKITWIN_CWAYLAND_H

#include <stdint.h>
#include <wayland-client.h>
#include <wayland-cursor.h>
#include <xkbcommon/xkbcommon.h>
#include "xdg-shell-client-protocol.h"
#include "xdg-decoration-unstable-v1-client-protocol.h"
#include "pointer-gestures-unstable-v1-client-protocol.h"

/// `wl_registry_bind` for the interfaces this backend uses, looked up by the name the
/// registry advertises (Swift cannot take the address of the imported `wl_*_interface`
/// constants). Returns NULL for an unknown interface name.
void *appkitwin_wl_registry_bind(struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version);

/// `MAP_FAILED` for Swift callers of `mmap`.
void *appkitwin_mmap_failed(void);

#endif
