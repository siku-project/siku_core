# siku_core

The core of the SIKU ecosystem — a modular, high-performance foundation for immersive FiveM roleplay experiences. Built with clean architecture, modern Lua 5.4 standards, scalability, and long-term maintainability.

![Version](https://img.shields.io/badge/version-1.0.0-4785bd)
![FiveM](https://img.shields.io/badge/fx__version-cerulean-4785bd)
![Lua](https://img.shields.io/badge/Lua-5.4-4785bd)

## Features

- **Lazy in-VM SDK** — one shared script gives every resource the global `Siku` table. A module compiles inside the consumer's own VM on first access and never before: `Siku.cron` costs nothing to the resource that never schedules anything.
- **22 library modules** — callbacks, cameras, classes, cron, spatial zones, timers, vehicles, logging and more, each loaded for the side (shared / client / server) that actually uses it.
- **Stateful services** — cache, permissions, bucket, command, migration and persistence live once in the core and are reached through the same `Siku.*` namespace.
- **Full RBAC** — roles with inheritance, wildcard permissions with negation, expiring assignments, an audit log, first-boot seeding and a hierarchy-checked `/setrole` command.
- **Additive migrations** — resources declare their schema; the core creates missing tables, columns and foreign keys under a global lock, never altering or dropping what exists.
- **Typed commands** — argument parsing with types, bounds, choices and durations, permission gating, cooldowns, and suggestions pushed to the chat.
- **User & character lifecycle** — connected players cached with their active character, playtime tracked, positions persisted, cleaned up on disconnect.
- **Routing buckets** — instance management with lockdown modes, per-player instances and automatic cleanup.
- **World adjustments** — a single configurable client module for HUD components, ped/vehicle density, dispatch, scenarios, health regen, PvP and Discord Rich Presence.
- **Resilient by design** — cron jobs, spatial ticks, intervals and migrations are isolated so one failing callback never kills the subsystem.

## Dependencies

| Resource | Required | Purpose |
|---|---|---|
| [oxmysql](https://github.com/CommunityOx/oxmysql) | Yes | Database access for migrations, persistence and RBAC. |

## Installation

Pure Lua — nothing to build. Download the latest [release](https://github.com/siku-project/siku_core/releases) or clone the repository into your resources folder.

### server.cfg

```cfg
ensure oxmysql
ensure siku_core
```

`siku_core` must be started before every other SIKU resource.

## Using the SDK

A consumer declares one shared script and gets the whole namespace:

```lua
shared_scripts {
  '@siku_core/init.lua',
}
```

```lua
-- Anywhere, on the right side:
Siku.print.info('Hello from %s', GetCurrentResourceName())

Siku.timers.setInterval(5000, function()
  Siku.print.debug('five seconds')
end)

local dependency = Siku.version.checkDependency('siku_core', '0.3.0')

if not dependency.ok then
  Siku.print.throw(dependency.message)
end
```

`Siku.<module>` resolves lazily: the module's `shared.lua` and side-specific file compile into the calling resource's VM on first access. A plain-table return becomes a namespace; services fall through to the core. `Siku.config.<name>` reads the core config files shipped to consumers, and `T(key, ...)` translates from the **calling** resource's `translations/<language>.lua`.

## Library modules

| Module | Side | What it does |
|---|---|---|
| `callback` | shared | Request/response over the network, with timeouts and server-side rate limiting. |
| `camera` | client | Scripted camera registry: eased moves, shakes, DOF, entity/coord orbits, spline paths — auto-destroyed on resource stop. |
| `class` | shared | Single-inheritance class factory: `Siku.class`, `.new`, `.super`, `isInstance`. |
| `controls` | client | Refcounted disabling of game controls, per calling resource. |
| `cron` | server | Full cron expressions (steps, ranges, named days, last day of month) on a minute scheduler; each job runs isolated. |
| `entity` | both | Closest / nearby objects, peds and vehicles, distance-sorted with filters. |
| `isCallable` | shared | Callable check that tolerates the `__call` tables functions become across exports. |
| `keybind` | client | Keybinds in the GTA settings with press/release callbacks, enable/disable, `isPressed`. |
| `locale` | shared | `T(key, ...)` — loads the calling resource's translations and formats the arguments. |
| `math` | shared | Relative coords, number/currency formatting, lerps and interpolators, plus a seeded PRNG: weighted choice, shuffle, UUID v4/v7. |
| `notification` | both | Guarded proxy to [`siku_notification`](https://github.com/siku-project/siku_notification). |
| `player` | both | Closest / nearby players; identifiers on the server. |
| `print` | shared | Leveled color logger (`error` → `debug`, `throw`), filtered by the `siku:logLevel` convar, cycle-safe serialization. |
| `progress` | shared | Guarded facade over [`siku_progress`](https://github.com/siku-project/siku_progress): every family, every control. |
| `raycast` | client | Shape tests from coordinates, from the camera or along an entity's forward vector. |
| `spatial` | both | Point-in-shape geometry, a cell-bucketed grid and a zone registry; client-side enter/exit tracking, proximity points, shared per-frame tick, debug markers. |
| `streaming` | client | Blocking loaders for models, anims, PTFX, scaleforms and weapon assets, with timeouts. |
| `table` | shared | `contains`, `deepClone`, `filter`, `find`, `freeze`, `map`, `merge`, `size`… |
| `timers` | shared | Throw-tolerant `setInterval` / `updateInterval` / `clearInterval`, plus full timer objects with pause and resume. |
| `vehicle` | both | Full vehicle property get/set (mods, colors, damage, plate), driven server → client through state bags. |
| `version` | shared | Semver dependency checks that never raise, and a GitHub release check. |
| `waitFor` | shared | Polls a condition until it answers or throws on timeout. |

## Services

Stateful singletons living in the core, reached through the same namespace:

| Service | What it owns |
|---|---|
| `Siku.cache` | Connected users and their active character, indexed by session and license. |
| `Siku.permissions` | The whole RBAC: checks, wildcard matching, role management, audit log. |
| `Siku.bucket` | Routing buckets: creation, lockdown modes, per-player instances, cleanup. |
| `Siku.command` | Typed command registration, permission gating, cooldowns, chat suggestions. |
| `Siku.migration` | Additive schema migrations, with cross-resource dependencies and a global lock. |
| `Siku.persistence` | Position and playtime capture, character and user writes. |

The `Siku.User` and `Siku.Character` classes stay inside the core: consumers receive cached instances as data and act on them through the services.

## Character lifecycle contract

The core does not decide when a character enters play — a character resource (such as [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter)) does, by firing:

| Event | Payload | Effect |
|---|---|---|
| `siku:server:createUserInstance` | `sessionId, userData` | Builds and caches the `User`. |
| `siku:server:createCharacterInstance` | `sessionId, characterData` | Builds the `Character`, makes it active, grants the default role on first entrance. |

Other resources listen to the same events to load what belongs to the character — that is how the inventory and the status system come alive.

## Database

`config/migration.lua` declares the core schema, applied on startup: `users`, `characters`, `roles`, `permissions`, `role_permissions`, `character_roles` and `rbac_audit_log`, with indexes and cascading foreign keys.

## Configuration

All options live in `config/` and are documented inline.

| File | Scope | Options |
|---|---|---|
| `config/callback.lua` | consumers | Callback timeout and rate limiting. |
| `config/camera.lua` | consumers | Camera defaults. |
| `config/spatial.lua` | consumers | Grid cell size and tracking defaults. |
| `config/version.lua` | consumers | Release check toggle. |
| `config/translation.lua` | core | `language` (`fr` / `en`) for the core's own strings. |
| `config/world.lua` | client | HUD removals, densities, dispatch, scenarios, PvP, Rich Presence. |
| `config/migration.lua` | server | The core schema. |
| `config/permissions.lua` | server | Role seeding and defaults. |
| `config/connection.lua` | server | Hardcap enforcement. |

## Conventions

The ecosystem follows one naming scheme, enforced across resources:

- Events: `siku:<context>:<name>` for cross-resource contracts, `<resource>:<side>:<name>` internally.
- State bags: `siku:state:<name>`.
- Callbacks: `siku:callback:<name>`.

## Ecosystem

Resources built on this core: [`siku_chat`](https://github.com/siku-project/siku_chat), [`siku_notification`](https://github.com/siku-project/siku_notification), [`siku_progress`](https://github.com/siku-project/siku_progress), [`siku_inventory`](https://github.com/siku-project/siku_inventory), [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter), [`siku_status`](https://github.com/siku-project/siku_status), [`siku_hud`](https://github.com/siku-project/siku_hud) — started from [`Siku_Boilerplate`](https://github.com/siku-project/Siku_Boilerplate).

## Credits

Part of the [SIKU project](https://github.com/siku-project) — © Siku Studio.
