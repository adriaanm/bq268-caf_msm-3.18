# BQ268 Kernel — Project Instructions

## Reproducibility

Every repeated command must be tracked in git as a self-describing recipe. The `justfile` is the single entry point for all build, flash, and analysis steps. If you find yourself running a command more than once, add it as a `just` recipe.

Run `just` to list all available recipes.

## Workflow: Commit Before Flash

Every kernel change that will be flashed MUST follow this discipline:

1. **Commit first** — create a git commit with the changes before building/flashing
2. **Build and flash** — `just bootimg`, then `just fastboot-boot`
3. **Record outcome** — amend the commit message with the boot test result:
   - `BOOT TEST: PASS` — device boots successfully
   - `BOOT TEST: FAIL (description)` — device did not boot, with brief failure description
   - `BOOT TEST: PARTIAL (description)` — boots but with issues
4. **Record experiment** — `just note "PASS: description"` (records on HEAD)

## Tasks & Experiments — ALWAYS use `just` recipes

**IMPORTANT: Never use raw `git notes` commands.** Always use the `just` recipes:

- **`just tasks`** — show current tasks
- **`just task-add "description"`** — add a new task
- **`just task-start "pattern"`** — mark a task in-progress
- **`just task-done "pattern"`** — mark a task done
- **`just experiments`** — show experiment log
- **`just note "message"`** — record an experiment outcome on HEAD

## Toolchain

**GCC 4.9.4 only.** Clang 14 cross-compilation was attempted but the resulting kernel does not boot. The build completes but the device hangs with no output. Diagnostics were inconclusive:
- pstore/ramoops can't help because the device has no watchdog from the bootloader (only cold reset available, which wipes RAM)
- fbcon was tested but the display never turned on, so the crash is before display init
- Static analysis (disassembly, section layout, ABI flags) showed no obvious issues
- The Clang build infrastructure remains in the justfile (`build-clang`, `bootimg-clang`) if revisited later

**Always use `bootimg-gcc` for flashable images.**

## Known Issues

- MBHC disable via kernel code (`of_property_read_bool` in msm8952.c) crashes on boot — likely GCC 4.8 miscompilation. Need alternative approach.
