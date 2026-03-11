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
4. **Update git notes** — record experiment details on the commit:
   ```bash
   git notes --ref=experiments add -m "experiment: ...
   hypothesis: ...
   outcome: ..." <sha>
   ```

## Git Notes

We use two note namespaces for out-of-band tracking:

- **`experiments`** — boot test log attached to the commit that was flashed
- **`tasks`** — lightweight task tracking attached to HEAD

View: `just experiments` or `git log --oneline --notes=experiments --notes=tasks`

Update experiment outcome: `git notes --ref=experiments edit <sha>`

Update tasks: `git notes --ref=tasks edit HEAD`

## Known Issues

- MBHC disable via kernel code (`of_property_read_bool` in msm8952.c) crashes on boot — likely GCC 4.8 miscompilation. Need alternative approach.
