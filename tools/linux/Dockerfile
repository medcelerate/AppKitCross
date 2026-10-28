# Linux build and headless run of AppKitWin (Milestone 8).
#   docker build -t appkitwin-linux -f tools/linux/Dockerfile .
#   docker run --rm appkitwin-linux            # builds, runs the tests on the host backend,
#                                              # then runs HelloWindow under Xvfb and writes a screenshot
#   docker run --rm appkitwin-linux bash tools/linux/run.sh --wayland
#                                              # ... and additionally under a headless sway (Wayland)
FROM swift:6.2-noble
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config libcairo2-dev libpango1.0-dev libx11-dev \
        libwayland-dev wayland-protocols libxkbcommon-dev \
        xvfb x11-apps imagemagick fonts-dejavu-core \
        sway grim xkb-data dmz-cursor-theme \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m appkitwin
WORKDIR /src
COPY . .
RUN swift build 2>&1 | grep -E "error:|Build complete|Compiling" | grep -v "^\[" | head -120 ; test -x .build/debug/HelloWindow
CMD ["bash", "tools/linux/run.sh"]
