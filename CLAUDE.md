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

## Toolchain Status

We are migrating from GCC 4.9.4 to Clang 14. **Only GCC builds boot right now.** The Clang-built kernel does not boot (unknown cause — pstore is now enabled to capture crash logs from Clang boots).

- `just bootimg` — builds with GCC (working)
- `just build` — builds with Clang (does NOT boot yet)
- `just build-gcc` — builds with GCC explicitly

Always use GCC (`bootimg` / `build-gcc`) for images you intend to flash, until the Clang boot issue is resolved.

## Known Issues

- MBHC disable via kernel code (`of_property_read_bool` in msm8952.c) crashes on boot — likely GCC 4.8 miscompilation. Need alternative approach.
- Clang-built kernel doesn't boot — need to capture pstore crash log to diagnose.
