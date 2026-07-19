# Contributing to siku_core

## Branch model

Two permanent branches, and nobody pushes to either of them.

```
feature/xxx ──PR──> dev ──PR──> main
```

- **`main`** holds released work only: clean, stable, verified. It is only ever updated by a pull request coming from `dev`.
- **`dev`** is the integration branch. It is only ever updated by a pull request coming from a short-lived branch.

Both are protected: direct pushes are rejected, force pushes are rejected, deletion is rejected. This applies to everyone, administrators included.

## Working on something

```bash
git checkout dev
git pull
git checkout -b feature/my-thing
```

Work, commit, then:

```bash
git push -u origin feature/my-thing
gh pr create --base dev
```

CI runs on every push, so a branch is checked before its pull request even exists. Once the pull request is approved and green, merge it. The source branch is deleted automatically.

Branch naming follows the intent: `feature/`, `fix/`, `refactor/`, `chore/`.

## Releasing to main

```bash
gh pr create --base main --head dev
```

Only `dev` may target `main`. A pull request from any other branch is rejected by the `guard` check, because GitHub cannot express that rule natively.

`dev` is squash-merged into itself from feature branches, so its history stays one commit per pull request. `dev` into `main` uses a merge commit, so every release is a visible point in `main`'s history.

## Commit messages

```
TYPE - Scope: what changed
```

`FEAT`, `FIX`, `REFACTOR`, `CHORE` in capitals. The pull request number is appended automatically on squash.

## What CI checks

| Check | What it does |
|---|---|
| `syntax` | Compiles every `.lua` file with Lua 5.4. Catches syntax errors and anything the 5.4 runtime rejects. |
| `manifest` | Verifies `fxmanifest.lua` declares files that exist, that no tracked Lua file is left unloaded, and that no file is both listed explicitly and matched by a glob. That last one silently loads a file twice and resets its state. |
| `guard` | Enforces the branch flow described above. |

There is deliberately no linter and no formatter. They are reconsidered when they earn their place.

## Code rules

Full annotations on every function, `<const>` wherever a value never changes, `local function` for private helpers, at most three nested conditionals, two-space indentation, and no comments in code other than `---` annotations.

New files must be declared in `fxmanifest.lua`. Inside `lib/`, never read another file's state at load time — keep cross-file access inside function bodies, so the manifest globs stay order-independent.
