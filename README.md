# siku_core

The core of the SIKU ecosystem — a modular, high-performance foundation for immersive FiveM roleplay experiences. Built with clean architecture, modern Lua 5.4 standards, scalability, and long-term maintainability.

![Version](https://img.shields.io/badge/version-1.3.0-4785bd)
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
- **Job engine** — the single authority on jobs: resources declare their organisation (grades, permissions, legal or illegal), the core stores it, holds every membership per character, resolves permissions and duty, counts who is in, and tells the ecosystem what changed. Multi-job by design, no boss, no primary job.
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
| `Siku.cache` | Connected users and their active character, indexed by session, license and character id (`getSessionByCharacter`, `getCharacter`, `getCurrentCharacterId`). |
| `Siku.permissions` | The whole RBAC: checks, wildcard matching, role management, audit log. |
| `Siku.bucket` | Routing buckets: creation, lockdown modes, per-player instances, cleanup. |
| `Siku.command` | Typed command registration, permission gating, cooldowns, chat suggestions. |
| `Siku.migration` | Additive schema migrations, with cross-resource dependencies and a global lock. |
| `Siku.persistence` | Position and playtime capture, character and user writes. |
| `Siku.jobs` | The job engine: registry, memberships, grades, permissions, duty, counters, audit. See [Jobs](#jobs). |

The `Siku.User` and `Siku.Character` classes stay inside the core: consumers receive cached instances as data and act on them through the services.

## Character lifecycle contract

The core does not decide when a character enters play — a character resource (such as [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter)) does, by firing:

| Event | Payload | Effect |
|---|---|---|
| `siku:server:createUserInstance` | `sessionId, userData` | Builds and caches the `User`. |
| `siku:server:createCharacterInstance` | `sessionId, characterData` | Builds the `Character`, makes it active, grants the default role on first entrance. |

In return the core fires:

| Event | Payload | When |
|---|---|---|
| `siku:server:releaseCharacterInstance` | `sessionId, characterId` | The character leaves play: on a switch, before the next one is activated, and on disconnect, after the core saved it and before the cache forgets it. |

Other resources listen to these events to load and write back what belongs to the character — that is how the inventory, the status system and the HUD preferences come alive and go to sleep, without keeping their own copy of who plays what.

## The character

`Siku.cache.getCurrentCharacter(sessionId)` answers the `Character` in play, carrying the whole row: `id`, `userId`, `sessionId`, `firstName`, `lastName`, `dob` (`YYYY-MM-DD`), `gender`, `height`, `nationality`, `birthplace`, `pedModel`, `appearance` (decoded, or nil), `isDead`, `x`, `y`, `z`, `heading`, `lastPlayed`, `createdAt`.

| Method | Purpose |
|---|---|
| `getFullName()`, `getAge()` | Read from the identity. |
| `getPublic()` | The view that leaves the server: identity and death state, nothing to act on. |
| `setIdentity({ firstName?, lastName?, dob?, gender?, height?, nationality?, birthplace? })` | Validates and writes at once, republishes, fires `siku:character:identityChanged`. |
| `setPedModel(model)`, `setAppearance(look)` | Written at once. |
| `setDead(dead)` | Written at once, republished, fires `siku:character:deathChanged(sessionId, characterId, dead)`: the seam a death resource, the status decay and the voice restriction hang on. |
| `getPosition()`, `setPosition()`, `getPlaytime()`, `hasPermission()`, `getRoles()`, `assignRole()`, `revokeRole()` | As before. |

Position, playtime and death state are also captured by `Siku.persistence` on its passes; identity, model and look are written by their setters, so a save pass never has to catch up on a name.

The death state keeps itself accurate: the core client watches the local ped and reports each change through `siku:server:deathStateChanged`, the server checks its own copy of the ped before calling `setDead`. Whether a character left dead comes back dead is the character resource's decision (`deathPersistence` in [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter)); the core only tells the truth about the flag.

The public view is replicated on the player's state bag `siku:state:character` the moment the character enters play, so every client reads who anyone is without asking: `Siku.player.getCharacter()` for the local player, `Siku.player.getCharacter(playerId)` or `Siku.player.getCharacterByServerId(serverId)` for another one. The `User` carries `name` and `ip` from the identifiers on top of the row.

## Jobs

The core owns everything structural about jobs; the resources own the gameplay. A character holds zero, one or several memberships, each with a grade; a grade is a set of permissions and a rank; a permission is a concrete capability that may need the character on duty. Legal jobs have a duty, illegal organisations do not. A character with no legal job is unemployed, whatever else it belongs to. Nothing is stored for the unemployment, no grade is a boss, no job is the main one.

### Declaring a job

A resource registers its organisation once at start. The first registration writes the definition; the next ones only add what the declaration gained, so an edit made in game (a renamed grade, a new one, a permission granted) survives every restart. The job is live until the resource stops, and dormant afterwards: members keep their grades, nobody keeps a duty, no permission resolves.

```lua
local police = Siku.jobs.get('police')

police:register({
  label = 'Los Santos Police Department',
  permissions = {
    'recruit',
    'management.open',
    { name = 'armory.access', duty = true },
    { name = 'dispatch.receive', duty = true },
    { name = 'garage.use', duty = true },
  },
  grades = {
    { name = 'cadet', label = 'Cadet', rank = 1, permissions = { 'garage.use' } },
    { name = 'officer', label = 'Officer', rank = 2, permissions = { 'garage.use', 'armory.access', 'dispatch.receive' } },
    { name = 'sergeant', label = 'Sergeant', rank = 3, permissions = { 'garage.*', 'armory.*', 'dispatch.*', 'recruit' } },
    { name = 'commander', label = 'Commander', rank = 4, permissions = { '*' } },
  },
})
```

A `domain = 'illegal'` turns the declaration into an organisation without duty. Grades are named, never numbered outside the engine: the rank only orders them and bounds what a member may do to another. Permissions are the job's own vocabulary: the core keeps no catalogue and gives no meaning to a name, it stores what the job declared, resolves it with the same wildcards and negation as the staff RBAC, scoped to the job, and answers `hasPermission`. A police can ask for `dispatch.receive`, a family for `stash.manage`; what a permission allows is decided where it is checked.

### Acting on a job

`Siku.jobs.get(name)` answers a handle whose reads are copies and whose writes go back to the core: `getDefinition`, `getGrades`, `getMembers`, `getOnlineMembers`, `count`, `hasMember`, `getMembership`, `hasPermission(characterId, permission)`, `isOnDuty`, `hire`, `fire`, `setGrade`, `setDuty`, and the definition edits a patron menu needs: `setLabel`, `createGrade`, `updateGrade`, `deleteGrade` (members move to the grade just below), `declarePermission`, `removePermission`, `grantPermission`, `revokePermission`. Every function also exists flat on `Siku.jobs` with the job name first.

A membership mutation takes a context `{ performedBy, enforceHierarchy }`. When the actor is a member of the job, the engine asks for a rank above the one touched: nobody hires, promotes or dismisses at or above their own grade. Staff and code acting from outside the job, or a context with `enforceHierarchy = false`, go through. Whether the actor may act at all is the job's rule, checked with its own permissions before calling. Every hire, dismissal, grade change and definition edit lands in `job_audit_log` with the actor.

### Following a job

| Event | Payload |
|---|---|
| `siku:jobs:registered` | `jobName, definition` |
| `siku:jobs:deactivated` | `jobName` |
| `siku:jobs:definitionChanged` | `jobName, definition` |
| `siku:jobs:memberAdded` | `characterId, jobName, gradeName, sessionId?` |
| `siku:jobs:memberRemoved` | `characterId, jobName, sessionId?` |
| `siku:jobs:gradeChanged` | `characterId, jobName, gradeName, previousGradeName, sessionId?` |
| `siku:jobs:dutyChanged` | `sessionId, characterId, jobName, onDuty` |
| `siku:jobs:unemploymentAllowance` | `sessionId, characterId, amount` — temporary, until the economy |

The duty lives in memory and ends with the session. Taking a duty when the legal `maxOnDuty` is reached is refused, not switched: the job resource decides what to offer.

### On the client

Nothing goes through a state bag: a character receives its own memberships and nobody else's. `Siku.jobs.getMine()`, `get(job)`, `has(job)`, `isOnDuty(job)`, `getDuties()`, `isUnemployed()` read the local copy; `onChanged(handler)` follows it; `getCounts(job)`, `getDefinition(job)` and `getMembers(job)` ask the server, the last one only answered to a member of the job.

### Commands

| Command | Permission | Effect |
|---|---|---|
| `/setjob <player> <job> <grade>` | `jobs.manage` | Hires the character or moves its grade, by grade name. |
| `/unsetjob <player> <job>` | `jobs.manage` | Removes the character from the job. |
| `/jobs [player]` | own, `jobs.manage` for others | Lists the memberships. |
| `/duty <job>` | member | Takes or leaves the duty of a legal job. |

## Database

`config/migration.lua` declares the core schema, applied on startup: `users`, `characters`, `roles`, `permissions`, `role_permissions`, `character_roles`, `rbac_audit_log`, and for the job engine `jobs`, `job_grades`, `job_permissions`, `job_grade_permissions`, `job_memberships` and `job_audit_log`, with indexes and cascading foreign keys.

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
| `config/jobs.lua` | server, consumers | Domain limits (`maxJobs`, `maxOnDuty`, `false` for none), the temporary unemployment allowance, auditing. |

## Conventions

The ecosystem follows one naming scheme, enforced across resources:

- Events: `siku:<context>:<name>` for cross-resource contracts, `<resource>:<side>:<name>` internally.
- State bags: `siku:state:<name>`.
- Callbacks: `siku:callback:<name>`.

## Ecosystem

Resources built on this core: [`siku_chat`](https://github.com/siku-project/siku_chat), [`siku_notification`](https://github.com/siku-project/siku_notification), [`siku_progress`](https://github.com/siku-project/siku_progress), [`siku_inventory`](https://github.com/siku-project/siku_inventory), [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter), [`siku_status`](https://github.com/siku-project/siku_status), [`siku_hud`](https://github.com/siku-project/siku_hud) — started from [`Siku_Boilerplate`](https://github.com/siku-project/Siku_Boilerplate).

## Credits

Part of the [SIKU project](https://github.com/siku-project) — © Siku Studio.
