# Linux build and headless run of AppKitWin (Milestone 8).
#   docker build -t appkitwin-linux -f tools/linux/Dockerfile .
#   docker run --rm appkitwin-linux            # builds, runs the tests on the host backend,
#                                              # then runs HelloWindow under Xvfb and writes a screenshot
#   docker run --rm appkitwin-linux bash tools/linux/run.sh --wayland
#                                              # ... and additionally under a headless sway (Wayland)
# The container has no GPU: Mesa's lavapipe (mesa-vulkan-drivers, a CPU Vulkan 1.3
# implementation) backs the Metal module's Vulkan device (ADR-0012), libvulkan-dev gives the
# shim its headers, glslang-tools compiles HLSL to SPIR-V, and vulkan-validationlayers serve
# APPKITWIN_VULKAN_DEBUG=1. libdbus-1-dev builds the AT-SPI2 bridge (ADR-0013); dbus and
# at-spi2-core run a session bus and the accessibility registry under Xvfb, and
# python3-dbus drives tools/linux/atspi-probe.py against HelloWindow.
FROM swift:6.2-noble
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config libcairo2-dev libpango1.0-dev libx11-dev \
        libwayland-dev wayland-protocols libxkbcommon-dev \
        xvfb x11-apps imagemagick fonts-dejavu-core \
        sway grim xkb-data dmz-cursor-theme jq \
        libvulkan-dev libvulkan1 mesa-vulkan-drivers vulkan-validationlayers vulkan-tools glslang-tools \
        libdbus-1-dev dbus at-spi2-core python3-dbus \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m appkitwin
WORKDIR /src
COPY . .
RUN swift build 2>&1 | grep -E "error:|Build complete|Compiling" | grep -v "^\[" | head -120 ; test -x .build/debug/HelloWindow
CMD ["bash", "tools/linux/run.sh"]
