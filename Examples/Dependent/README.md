# Dependent

The smallest app that uses AppKitCross the way your own package does: a separate package
with `.package(path: "../..")` (use the Git URL in yours), a ten-line SwiftUI app and one
SwiftPM resource. CI builds it on Windows, Linux and macOS with a plain `swift build` and no
extra flags, bundles it with `swift package bundle`, and crashes it on purpose to check the
crash report (ADR-0046).

```bash
cd Examples/Dependent
swift build
swift run Dependent
swift package --allow-writing-to-package-directory bundle --product Dependent --zip
```

On Windows with Swift 6.2, CI adds `-j 1` to `swift build`: the 6.2 driver sometimes drops a
job when two start together (docs/ci-windows-runner.md). That is a property of the
toolchain, so the package cannot set it for you.
