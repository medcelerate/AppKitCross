#include "CWayland.h"
#include <string.h>
#include <sys/mman.h>

void *appkitwin_wl_registry_bind(struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    const struct wl_interface *iface = NULL;
    if (strcmp(interface, "wl_compositor") == 0) iface = &wl_compositor_interface;
    else if (strcmp(interface, "wl_shm") == 0) iface = &wl_shm_interface;
    else if (strcmp(interface, "wl_seat") == 0) iface = &wl_seat_interface;
    else if (strcmp(interface, "wl_output") == 0) iface = &wl_output_interface;
    else if (strcmp(interface, "xdg_wm_base") == 0) iface = &xdg_wm_base_interface;
    else if (strcmp(interface, "zxdg_decoration_manager_v1") == 0) iface = &zxdg_decoration_manager_v1_interface;
    if (!iface) return NULL;
    return wl_registry_bind(registry, name, iface, version);
}

void *appkitwin_mmap_failed(void) { return MAP_FAILED; }
