// The registration of ADR-0045 where the platform has no desktop to register with (the macOS
// host build: apps there are registered by LaunchServices).

import Foundation

#if !os(Windows) && !os(Linux)
func _platformRegisterApplication(_ plan: _AppRegistration, iconPNG: Data?) throws {
    throw PlatformWorkspaceError.unsupported("registering file types (LaunchServices registers macOS apps)")
}
func _platformUnregisterApplication(_ plan: _AppRegistration) throws {
    throw PlatformWorkspaceError.unsupported("registering file types (LaunchServices registers macOS apps)")
}
func _platformIsApplicationRegistered(_ plan: _AppRegistration) -> Bool { false }
#endif
