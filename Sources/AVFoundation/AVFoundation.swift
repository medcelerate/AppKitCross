// AVFoundation (ADR-0014): Apple's umbrella module name. The audio API lives in AVFAudio,
// as it does in Apple's SDK; `import AVFoundation` re-exports it so application code
// compiles unchanged. The video and asset halves of AVFoundation are not part of the port.

@_exported import AVFAudio
