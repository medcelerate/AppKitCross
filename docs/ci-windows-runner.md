# The Windows CI build that died without a word

From late October 2026 the "Windows build and tests" job (GitHub `windows-2022`, swift.org
Swift 6.2, 4 cores, 16 GB) failed now and then with `exit code 1`. The log ended in
AppKit's last compile warnings: no `error:`, no stack dump, no `Build complete!`. It happened
in the root `swift build` and in `tools/library-compat.sh`'s step 1, which builds AppKit a
second time. PRs 32 and 36 answered it with `-j 2`, resource dumps and one retry that
resumes the incremental build.

The runner was never killing anything. **Swift 6.2's driver (`swiftc.exe`) sometimes never
starts AppKit's separate emit-module job, and then exits 1 without a diagnostic.** It only
happens when the driver starts jobs concurrently, so the Windows builds now run one
compiler job at a time (`-j 1`) and the retries are gone. Two flag-level workarounds that
looked clean on AppKit alone failed in the full pipeline (below).

## What the old runs showed

All 278 CI runs from 2026-10-28 to 2026-11-10 were mined (the job logs through
`gh api .../actions/jobs/<id>/logs`). Of 53 failed Windows jobs:

| class | jobs | notes |
| --- | --- | --- |
| silent: AppKit's emit-module never finished | 26 | 13 root builds, 13 library-compat step 1. Always after `Compiling AppKit … Unimplemented.swift` (the last batch); `Emitting module AppKit` never printed. 1.5–12 min into the job, memory free afterwards (14 GB physical, 17 of 19.8 GB commit). |
| real compiler, linker or test errors | 26 | diagnostics present |
| toolchain download failed | 1 | setup action |

The retry hid most of it. Of 31 green Windows jobs after PR 36, **11 needed the root-build
retry and 20 the library-compat retry**. A from-scratch AppKit build failed more often than
it passed. Each resumed build ran `Emitting module AppKit` first (about 20 s on its own) and
then went on: the batches had all finished, and only the emit-module job was missing.

## Experiments

Each run was a matrix of from-scratch `swift build -c debug -j 2 --target AppKit -v` jobs on
`windows-2022` (`.github/workflows/ci-windows-experiment.yml`, removed again before
merging). Every job also had `tools/windows/frontend-monitor.ps1` running, Windows Error
Reporting local dumps switched on, and the Application/System event logs and Defender state
read afterwards. The monitor keeps a handle on every `swift-frontend`, `swiftc`,
`swift-build`, `swift`, `clang` and `lld-link` process, so it knows each one's exit code,
peak private bytes and lifetime, and it samples the system commit charge. A
response-file job is classified by the file's contents.

| run | variable (one each) | from-scratch AppKit builds failing | what it showed |
| --- | --- | --- | --- |
| E0 | control | 2 / 4 | Every frontend exited 0. Peak system commit 3.9 GB of a 19.3 GB limit; page file D:\pagefile.sys 2.9 GB, not auto-managed. No WER dumps, no crash or resource-exhaustion events. Defender real-time protection **off** on the image. In the failures, no AppKit emit-module frontend ran at all; in the passes it ran 13–23 s at ~435 MB. |
| E1 | control, plus driver processes monitored and stderr kept apart | 3 / 4 | In every failure `swiftc.exe` for AppKit exits **0x00000001** after 75–130 s, with the emit-module frontend never started; `swift-build` and `swift` just pass the 1 on. Nothing on stderr. |
| E2a | `-Xswiftc -driver-show-job-lifecycle` | 0 / 2 | Extra driver output changes the timing (a race). |
| E2b | `-Xswiftc -no-emit-module-separately` | **0 / 4** | No separate emit-module job; build time unchanged (204–287 s). |
| E2c | `-j 1` | **0 / 4** | No concurrency; 40% slower (367–408 s). |
| E3 | control (SwiftPM build, 3rd sample) | 2 / 4 | |
| E3b | AppKit's exact `swiftc.exe` command replayed outside SwiftPM, 3× per runner, from an empty `AppKit.build` | 8 / 12 replays | Reproduces without SwiftPM. The parseable output of a failed replay has `began`/`finished` for all 629 compile jobs, all exit status 0, and **no `emit-module` message at all**: the job was never started. In passing replays it is the second job started, right after batch 0. |
| E4 | `-Xswiftc -driver-force-response-files` | 0 / 4 | Every job through a response file, and the emit-module job ran each time (13–23 s). So the response file alone is not the trigger; this changes when each job's arguments are resolved and written. |

Controls overall: 7 of 12 SwiftPM builds and 8 of 12 bare replays failed. Every changed
variable gave 0 failures: 0 of 14 builds.

These runs built `--target AppKit` only. The full pipeline then ruled out both flag-level
workarounds:

| CI run on PR 55 | head | Windows flags | Windows result |
| --- | --- | --- | --- |
| 42929006283 | 9a3ff9d | `-j 2 -Xswiftc -no-emit-module-separately` | **failed, not silently.** AppKit built, then SwiftUI's `-merge-modules` job rejected its own partial modules: `type mismatch of function '…_DisclosureTriangleV4bodyQrvg' … -> @out some SwiftUI.View`. Merging partial modules does not handle opaque result types, so this flag cannot be used for the package. |
| 42932273289 | 1ff8cdd | same (merge of origin/main) | cancelled by the next push |
| 42932457104 #1 | 2aa4cd9 | `-j 2 -Xswiftc -driver-force-response-files` | failed in the toolchain download (setup action flake) |
| 42932457104 #2 | 2aa4cd9 | same | **failed silently: the same bug.** Exit 1 with no diagnostic at `[42/89]`, in CoreGraphics and Metal. With every job behind a response file, any module's job can be the one lost. E4's 4 of 4 was luck, and this points back at response-file creation as the throw site. |

macOS and both Linux jobs passed in every run. So the only measured clean setting with no
side effects is `-j 1`, where the driver never starts two jobs at once.

## Why the driver says nothing

swift-driver `release/6.2`,
[`Sources/SwiftDriverExecution/MultiJobExecutor.swift`](https://github.com/swiftlang/swift-driver/blob/release/6.2/Sources/SwiftDriverExecution/MultiJobExecutor.swift),
`ExecuteJobRule.executeJob`: the argument resolution (`resolver.resolveArgumentList`) and
`launchProcess` sit in one `do` block. If either throws before the job is reported started,
the `catch` emits a diagnostic only when the error `is DiagnosticData`, skips `jobFinished`
because `pendingFinish` is still false, and marks the job failed. The other jobs carry on, because
`cancelBuildIfNeeded` only looks at the result of a process that ran. At the end
`execute` throws `Driver.ErrorDiagnostics.emitted`, which the driver turns into exit 1,
although nothing was emitted.

What throws is not visible from outside: the error is dropped before anything prints it.
It happens before the job is reported started, so it is in resolving the job's arguments
or in launching its process. Of AppKit's jobs only the emit-module one has a command over
Windows' 32 KB limit (641 source paths; each batch job uses `-filelist` instead), so it
alone gets an `arguments-<sha256>.resp` file from
[`ArgsResolver.createResponseFileIfNeeded`](https://github.com/swiftlang/swift-driver/blob/release/6.2/Sources/SwiftDriver/Execution/ArgsResolver.swift).
That file is written `atomically: true` outside the resolver's lock while the first batch job
writes its file lists into the same temporary directory. E4 seemed to argue against that
(4 of 4 clean with every job behind a response file), but in the full pipeline the same
setting lost a job in a small module (run 42932457104 above). So response-file creation
under concurrent job starts is the most likely throw site. What the runs pin down:

- the trigger is two jobs starting together, since `-j 1` cures it and extra driver output
  hides it;
- only the emit-module job is lost;
- without a separate emit-module job there is no failure.

Finding the exact Win32 error needs an instrumented driver, and the fix belongs in
swiftlang/swift-driver: `executeJob` should emit any error it catches. This repository
can only avoid the job.

The earlier hypotheses, each ruled out by the runs above:

- **Address-space, commit or page-file limit:** peak commit 3.9 of 19.3 GB, no
  resource-exhaustion events, the failing job never even starts.
- **A crash with the dialog suppressed:** every process exit code is known, no dumps, no
  application-error events.
- **A type-checker stack overflow on one file:** the batches all finish with status 0. The
  last file in the log is just the last batch.
- **Job object or antivirus:** Defender real-time protection is off on the image, and
  nothing was terminated.
- **The `-j 2` batch mode:** close. It is the driver's concurrent job start, but in
  emit-module scheduling, not batch mode, and `-j 2` was never a memory fix.

## What CI does now

- Every Windows `swift build` and `swift test`, and `tools/library-compat.sh` on Windows,
  runs with `-j 1`. SwiftPM passes it to the driver, so no driver ever starts two jobs
  together. It costs time: in E2c a from-scratch AppKit build took 367–408 s against
  165–290 s with `-j 2`.
- The root build's retry and resource dumps are gone, and so is library-compat's verbose
  retry. A failure is real again.
- `tools/windows/frontend-monitor.ps1` stays for the next time a Windows build dies quietly.

When the toolchain moves past 6.2, try `-j 2` again on the experiment matrix. If several
from-scratch AppKit builds pass, the driver is fixed. The upstream fix belongs in
swiftlang/swift-driver: `MultiJobExecutor.executeJob` should emit any error it catches.
