## What this changes

<!-- One or two sentences. What does this pull request do, and why? -->

## Type

- [ ] FEAT — new capability
- [ ] FIX — corrects a defect
- [ ] REFACTOR — behaviour unchanged, structure improved
- [ ] CHORE — tooling, CI, documentation

## Checklist

- [ ] Branch was created from `dev`, and targets `dev` (only `dev` may target `main`)
- [ ] Every function carries its `---@param` / `---@return` annotations
- [ ] `<const>` on every value that never changes
- [ ] No comment inside the code, annotations excepted
- [ ] New files are declared in `fxmanifest.lua`, in the right block and the right order
- [ ] Load order still holds: nothing reads another file's state at load time

## How it was verified

<!-- Say what you actually ran, not what should work.
     "ensure siku_core on a local server, connected, checked the console" beats "should be fine". -->
