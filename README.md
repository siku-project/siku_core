# siku_core

The core of the SIKU ecosystem — a modular, high-performance foundation for immersive FiveM roleplay experiences. Built with clean architecture, modern Lua 5.4 standards, scalability, and long-term maintainability.

![Version](https://img.shields.io/badge/version-1.6.0-4785bd)
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
- **Accounts engine** — the foundation of every balance: accounts as first-class entities owned by a character or a job, zero or many per owner, a balance the core alone moves through atomic batches, a journal of every mutation, grants for characters who are not the owner, and states. The core knows an account exists, whom it belongs to and what it holds; the bank decides why the value moves.
- **Logs & tracing** — one API, `Siku.log`, for structured events, audits and spans from any resource on either side: entities resolved to characters and users, Lua errors and player sessions captured by the core, automatic tracing of SQL, callbacks and commands, served to the SIKU Agent over FXServer's HTTP port. See [Logs & tracing](#logs--tracing).
- **Licenses engine** — the structure of every permit: resources declare the licenses they deliver (a driving license, a weapon permit, a hunting license), the core holds who holds what, with a state, points, an issue date, an expiry and free metadata, journals every change and tells the ecosystem. The driving school decides when an exam is passed, the police decides when points are taken; the core only keeps the truth.
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
| `log` | both | Structured logs, audits, state transitions and spans, buffered and delivered to the core, then to the SIKU Agent and Telemetry. See [Logs & tracing](#logs--tracing). |
| `math` | shared | Relative coords, number/currency formatting, lerps and interpolators, plus a seeded PRNG: weighted choice, shuffle, UUID v4/v7. |
| `notification` | both | Guarded proxy to [`siku_notification`](https://github.com/siku-project/siku_notification). |
| `player` | both | Closest / nearby players; identifiers on the server. |
| `print` | shared | Leveled color logger (`error` → `debug`, `throw`), filtered by the `siku:logLevel` convar, cycle-safe serialization; `warn` and `error` also record a `script.warning` / `script.error` event. |
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
| `Siku.accounts` | The accounts engine: accounts, balances, atomic mutations, journal, grants, states. See [Accounts](#accounts). |
| `Siku.licenses` | The licenses engine: declared licenses, holdings per character, states, points, expiry, audit. See [Licenses](#licenses). |

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

## Accounts

The core owns the foundation of every balance and nothing of the banking. An account is an entity of its own: a stable id, an owner, a balance, a state, free metadata. A character or a job owns zero, one or many of them, nothing is created on its own, and the core never judges who may open one: that is the business of the resource asking, siku_banking first. Cash is not an account: it stays an inventory item, the inventory being the only truth about physical money.

The core knows an account exists, whom it belongs to and what it holds. It does not know what a bank, an ATM, a card, a PIN, a transfer, a loan, an interest, a salary or a fine is: the resources on top give the value its meaning.

### Opening and closing

```lua
local accountId = Siku.accounts.create('character', characterId)
local societyId = Siku.accounts.create('job', 'mechanic', { metadata = { product = 'business' } })

Siku.accounts.freeze(accountId, performedBy)
Siku.accounts.unfreeze(accountId, performedBy)
Siku.accounts.close(accountId, performedBy)
```

`create(ownerType, owner, options?)` takes `character` with a character id, or `job` with a job id or name, and `{ allowNegative?, metadata?, balance? }`; it answers the id or `nil` and a reason (`unknown_owner`, `invalid_amount`, ...). An account is `active`, `frozen` (it keeps its balance and refuses every mutation) or `closed` (its balance must be zero, and it never comes back). `delete` removes a closed account and its journal, for maintenance only. `setMetadata` replaces the free table a consumer keeps its own facts in, `setNegativeAllowed` decides per account whether the balance may go under zero, `AccountsConfig.allowNegative` deciding for the others.

### Moving value

```lua
Siku.accounts.credit(accountId, 500, { reason = 'salary', performedBy = actorId })
Siku.accounts.debit(accountId, 120, { reason = 'fine' })
Siku.accounts.transfer(fromId, toId, 1000, { reason = 'transfer' })

Siku.accounts.apply({
  { account = fromId, delta = -1000 },
  { account = feesId, delta = 10 },
  { account = toId, delta = 990 },
}, { reason = 'transfer with fees' })
```

Everything goes through `apply`: a batch of mutations, each an account and a whole delta, applied all or none. The core checks every account is active, every amount is whole and within `maxAmount`, every resulting balance stays allowed, holds a lock on the accounts touched, writes every balance and every journal line in one transaction, moves the cache and fires `siku:accounts:balanceChanged` per account. `credit`, `debit` and `transfer` are batches of one or two lines; `setBalance` writes the difference so the journal stays honest. Refusals come back as `false, reason`: `unknown_account`, `frozen`, `closed`, `invalid_amount`, `amount_limit`, `insufficient_balance`, `duplicate_account`, `batch_too_large`, `write_failed`.

Every mutation is journaled in `account_mutations` when `AccountsConfig.journal` is on: the batch, the delta, the balance after, the resource that asked, the reason it gave, the character acting. `getMutations(accountId, limit?)` reads the last ones. This is a technical trace the core keeps for itself; a statement a player reads is the bank's to build.

### Owners and access

Owning and acting are two different things. An owning character may do everything on its account. A character who is not the owner acts through a grant, a permission name the consumer invents, stored by the core and matched with the same wildcards and negation as every permission of the framework: `grant(accountId, characterId, 'use')`, `revoke(accountId, characterId, 'use'?)`, `hasGrant`, `getGrants`. A job account asks the job engine: `canAct(accountId, characterId, permission)` answers true for the owning character, for a matching grant, or when `Siku.jobs.hasPermission` answers the same name on the owning job. The core never names a permission: `treasury.use`, `account.manage` or anything else is the consumer's vocabulary.

`getCharacterAccounts(characterId)`, `getJobAccounts(job)`, `getByOwner(type, id)` and `getAccessible(characterId)` list what an owner holds and what a character can see. Every table leaving the engine is a copy.

### Following the accounts

| Event | Payload |
|---|---|
| `siku:accounts:created` | `accountId, account` |
| `siku:accounts:balanceChanged` | `accountId, balance, delta, batch, reason?, performedBy?` |
| `siku:accounts:stateChanged` | `accountId, state, previous, performedBy?` |
| `siku:accounts:metadataChanged` | `accountId, metadata` |
| `siku:accounts:accessChanged` | `accountId, characterId, permission, granted, performedBy?` |
| `siku:accounts:deleted` | `accountId, account` |

### On the client

Nothing goes through a state bag: a character receives the accounts it owns or holds a grant on, and nobody else's. `Siku.accounts.getMine()`, `get(id)`, `getBalance(id)`, `getOwned()` read the local copy, `onChanged(handler)` follows it; `fetch(id)`, `getJobAccounts(job)` and `getMutations(id)` ask the server, answered to the owner, a grant holder or a member of the owning job.

### Handle

`Siku.accounts.get(id)` answers a handle on the server whose reads are copies and whose writes go back to the core: `read`, `getBalance`, `getState`, `isActive`, `credit`, `debit`, `transferTo`, `setBalance`, `getMutations`, `freeze`, `unfreeze`, `close`, `setMetadata`, `setNegativeAllowed`, `grant`, `revoke`, `getGrants`, `isOwner`, `canAct`. Every function also exists flat on `Siku.accounts` with the account id first, `getAccount(id)` being the flat read.

### Commands

| Command | Permission | Effect |
|---|---|---|
| `/accounts [player]` | own, `accounts.manage` for others | Lists the accounts a character sees. |
| `/createaccount <player>` | `accounts.manage` | Opens an account owned by the character. |
| `/setbalance <account> <amount>` | `accounts.manage` | Sets a balance. |
| `/creditaccount <account> <amount>` | `accounts.manage` | Credits an account. |
| `/debitaccount <account> <amount>` | `accounts.manage` | Debits an account. |
| `/freezeaccount <account>` | `accounts.manage` | Freezes an account, or reopens a frozen one. |
| `/closeaccount <account>` | `accounts.manage` | Closes an account whose balance is zero. |

## Licenses

The core owns the structure of every license and nothing of its meaning. A license is a type a resource declares: a driving license, a weapon permit, a hunting license, a pilot license, a business license, whatever a resource wants to name. The core keeps no catalogue of its own. A character holds zero, one or several of them, each with a state, points when the license has some, an issue date, an expiry when the license has one, and free metadata. The driving school decides when the exam is passed, the police decides when points are taken or the license is suspended, the gun shop decides what a weapon permit allows: the core records, answers and tells.

### Declaring a license

A resource registers the licenses it delivers once at start. The first registration writes the definition, the next ones update it: the declaration is the truth, there is no in-game editing.

```lua
local drive = Siku.licenses.get('drive_car')

drive:register({
  label = 'Permis B',
  group = 'driving',        -- optional, for display only
  points = { max = 12 },    -- optional, no points without it
  validity = 1825,          -- optional, in days, never expires without it
})

Siku.licenses.get('weapon'):register({ label = "Permis de port d'arme", group = 'firearms', validity = 365 })
Siku.licenses.get('hunting'):register({ label = 'Permis de chasse', group = 'outdoor' })
```

The `group` is a label the core never interprets: it only lets a menu or an ID card put `drive_car`, `drive_bike` and `drive_truck` together. A license whose resource stopped stays known, readable, valid and issuable: it is a document, not a service. The flag only answers `isActive` and guards the declaration: a resource registering a license another running resource declared is refused with `owned_elsewhere`.

### Holding a license

A holding is `valid`, `suspended` or `revoked`. Two states are derived at read time: `expired` for a valid holding past its expiry, and back to `valid` for a suspension past its end. `isValid` answers true only for a holding that reads `valid`.

```lua
Siku.licenses.issue(characterId, 'drive_car', { performedBy = instructorId, reason = 'exam' })
Siku.licenses.suspend(characterId, 'drive_car', { endsAt = '2026-11-01 00:00:00', performedBy = officerId, reason = 'dui' })
Siku.licenses.lift(characterId, 'drive_car', { performedBy = officerId })
Siku.licenses.revoke(characterId, 'drive_car', { performedBy = judgeId, reason = 'court' })
Siku.licenses.removePoints(characterId, 'drive_car', 3, { performedBy = officerId, reason = 'speeding' })
```

`issue(characterId, license, options?)` creates the holding, `valid`, points at `max`, expiry from the license validity unless `expiresAt` or `validity` (days) says otherwise, metadata as given. On a holding read as `revoked` or `expired` it reissues and resets everything; on one read as `valid` or `suspended` it refuses with `already_held`. `suspend` takes an optional `endsAt` date, indefinite without it; `lift` ends a suspension; `revoke` is definitive and keeps the row for the history; `withdraw` deletes the row, for staff and maintenance. `setExpiry(characterId, license, expiresAt?)` prolongs, sets or clears the expiry; `setMetadata` replaces the free table.

Points are optional per license. `addPoints`, `removePoints` and `setPoints` move a `valid` holding between 0 and `max`; a license without points refuses with `no_points`. When the balance reaches zero the core fires `pointsExhausted` and nothing else: suspending, revoking or ignoring is the consumer's decision.

Every mutation takes a context `{ performedBy?, reason? }` and lands in `license_audit_log` when `LicensesConfig.audit` is on. Refusals come back as `false, reason`: `unknown_license`, `unknown_character`, `already_held`, `not_held`, `not_valid`, `not_suspended`, `revoked`, `expired`, `no_points`, `invalid_amount`, `invalid_date`, `invalid_options`, `invalid_metadata`, `invalid_context`, `unchanged`, `owned_elsewhere`, `not_ready`.

Dates travel as `YYYY-MM-DD HH:MM:SS` strings and are also accepted as unix timestamps.

### Reading

`exists`, `isActive`, `getDefinition(license)`, `getAll(group?)` describe the licenses. `getHoldings(characterId)` lists what a character holds, sorted by group then label; `getHolding(characterId, license)`, `has` (whatever the state), `isValid`, `getPoints` read one. `getHolders(license)` lists every holder with their state and `countHolders` counts them. A holding as it leaves the engine:

```lua
{
  license = 'drive_car', label = 'Permis B', group = 'driving',
  state = 'valid',           -- valid | suspended | revoked | expired
  points = 9, maxPoints = 12, -- nil for a license without points
  issuedAt = '2026-10-12 18:00:00',
  expiresAt = '2031-10-11 18:00:00', -- nil when it never expires
  suspendedUntil = nil,      -- a date while suspended for a time
  issuedBy = 42,             -- nil for the console or code
  metadata = {},
}
```

### Following the licenses

| Event | Payload |
|---|---|
| `siku:licenses:registered` | `name, definition` |
| `siku:licenses:deactivated` | `name` |
| `siku:licenses:issued` | `characterId, license, holding, sessionId?` |
| `siku:licenses:suspended` | `characterId, license, endsAt?, sessionId?` |
| `siku:licenses:lifted` | `characterId, license, sessionId?` |
| `siku:licenses:revoked` | `characterId, license, sessionId?` |
| `siku:licenses:expired` | `characterId, license, sessionId?` |
| `siku:licenses:withdrawn` | `characterId, license, sessionId?` |
| `siku:licenses:pointsChanged` | `characterId, license, points, delta, reason?, performedBy?, sessionId?` |
| `siku:licenses:pointsExhausted` | `characterId, license, sessionId?` |
| `siku:licenses:metadataChanged` | `characterId, license, metadata` |

A suspension reaching its end and a holding reaching its expiry are noticed by a minute cron for characters in play, which fires `lifted` or `expired` and refreshes the client. Offline, the derived state is enough.

### On the client

Nothing goes through a state bag: a character receives its own holdings and nobody else's, already derived by the server. `Siku.licenses.getMine()`, `get(license)`, `has(license)`, `isValid(license)`, `getPoints(license)` read the local copy, `isSynced()` says whether it arrived, `onChanged(handler)` follows it; `getDefinition(license)` and `getAll(group?)` ask the server. Another character's licenses never reach a client: a police check happens on the server.

### Handle

`Siku.licenses.get(name)` answers a handle on the server whose reads are copies and whose writes go back to the core: `register`, `exists`, `isActive`, `getDefinition`, `getHolders`, `countHolders`, `isHeldBy`, `isValidFor`, `getHolding`, `getPoints`, `issue`, `suspend`, `lift`, `revoke`, `withdraw`, `setMetadata`, `setExpiry`, `addPoints`, `removePoints`, `setPoints`. Every function also exists flat on `Siku.licenses` with the character id first and the license name second.

### Commands

| Command | Permission | Effect |
|---|---|---|
| `/licenses [player]` | own, `licenses.manage` for others | Lists the holdings with their state and points. |
| `/grantlicense <player> <license>` | `licenses.manage` | Issues, or reissues an expired or revoked one. |
| `/revokelicense <player> <license>` | `licenses.manage` | Revokes. |
| `/suspendlicense <player> <license> [duration]` | `licenses.manage` | Suspends for a duration (`30m`, `2h`, `7d`), or until lifted. |
| `/liftlicense <player> <license>` | `licenses.manage` | Lifts a suspension. |
| `/licensepoints <player> <license> <delta>` | `licenses.manage` | Adds or removes points. |

## Logs & tracing

`Siku.log` is the one entry point for observability. A resource records what happened; the core enriches it, buffers it and serves it to the [SIKU Agent](https://github.com/siku-project/siku-agent), which ships it to SIKU Telemetry and the Control Center. Nothing here ever blocks a tick: a call builds one table and queues it, delivery happens later in batches, and when nobody collects the records the buffer fills, drops the oldest and counts them.

### Writing logs

```lua
Siku.log.info('Cargo delivered', { route = 'docks', weight = 12.5 })
Siku.log.warn('Low stock', { item = 'water' })
Siku.log.error('Vehicle spawn failed', { model = 'adder' }, { outcome = 'failure' })
```

`trace`, `debug`, `info`, `warn`, `error` and `fatal` take a message, an optional table of data and optional options. The level is the technical severity; the outcome (`success`, `failure`, `denied`, `cancelled` or any short word) is a separate fact.

### Structured events

```lua
Siku.log.emit('inventory.transfer', {
  outcome = 'success',
  data = {
    items = { { name = 'water', count = 2 }, { name = 'radio', count = 1 } },
    reason = 'gift',
  },
  entities = {
    { type = 'player', id = source, role = 'actor' },
    { type = 'player', id = target, role = 'target' },
    { type = 'vehicle', id = netId, role = 'container', label = 'Sultan RS', plate = 'ABC 123' },
  },
})
```

- The event name is stable, lowercase, dotted: `domain.action`.
- `data` is free: scalars, lists and nested tables, bounded by `config/log.lua` (depth, keys, string length, size). The first level is filterable in the Control Center, the whole value stays readable.
- `entities` name who and what was involved, with a `type`, an `id`, a `role` and an optional `label`. A `player` entity carrying a session id is resolved by the core into the character (`character`, id and full name) and the user (`user`, id and player name) at that moment, so the event stays readable days later when the session id has been reused. Any other type is kept as given.
- `message` is optional. Known events are rendered by the Control Center from their data; unknown ones show their name and attributes.
- `dedupe = <ms>` with an optional `key` suppresses identical repeats inside the window and reports how many were suppressed.

The core adds the resource, the origin (`server` or `client`), the timestamp, the trust level and the trace context when the call happens inside a span.

### Audit events

```lua
Siku.log.audit('bank.transfer', {
  outcome = 'success',
  data = { amount = 2500, reason = 'rent' },
  entities = {
    { type = 'account', id = fromId, role = 'source' },
    { type = 'account', id = toId, role = 'destination' },
    { type = 'player', id = source, role = 'actor' },
  },
})
```

Audit events are server only, kept longer by Telemetry and never produced by a client: a client calling `Siku.log.audit` records a plain script event flagged `declaredAudit`. The core audits its own sensitive operations: role and permission changes, account mutations, job memberships and grades, licenses, and every command guarded by a permission.

### State transitions

For situations that persist, record the transition rather than every check:

```lua
Siku.log.state('vehicle.speeding:' .. netId, speed > 180, {
  value = speed,
  holdMs = 2000,
  entities = { { type = 'vehicle', id = netId, role = 'subject' }, { type = 'player', id = driver, role = 'actor' } },
})
```

The first active call records `vehicle.speeding.started`; later active calls only track the maximum; once inactive for `holdMs`, `vehicle.speeding.ended` carries the duration and the maximum. `enter` and `exit` override the event names. Detection stays in the resource; the core only records what it was told.

### Client side

The same API works in client scripts. Records are batched, sent to the server at most once per second and well under FXServer's network limits, then validated and rate limited per player. Client records are `declared`: the actor is resolved from the session by the server, the category is always `script`, and whatever the client claims about itself is kept as a claim.

### Tracing

```lua
local ok, reason = Siku.log.span('bank.transfer', function()
  local from = MySQL.single.await('SELECT balance FROM accounts WHERE id = ?', { fromId })
  Siku.log.info('balance checked', { balance = from.balance })
  return Siku.accounts.transfer(fromId, toId, amount, { performedBy = characterId })
end, { attributes = { amount = amount } })
```

A span measures one operation. Spans nest, errors are recorded then rethrown, and everything logged inside carries the trace and span ids. The core instruments on its own what it controls: oxmysql queries (`db.query`, statement without parameters), callbacks (client and server side, with the context carried across the network), commands, and threads or timers started inside a span. `Siku.log.context()` returns the current ids for anything else. Root spans opened by the core itself are sampled at `tracing.autoSampleRate`, explicit spans at `tracing.sampleRate`.

There is no instruction-level hook in FXServer's Lua sandbox: a trace shows the instrumented operations only, never invented steps.

### What the core records by itself

| Event | Category | When |
|---|---|---|
| `core.ready`, `core.stopping` | system | The core finished initialising, or stops. |
| `resource.started`, `resource.stopped`, `resource.start_failed` | system | Any resource of the server. |
| `player.joined`, `player.dropped` | system | A session starts (identifiers listed in `config/log.lua`) or ends (reason, cause, duration, character). |
| `character.activated` | system | A character enters play. |
| `script.error`, `script.warning`, `script.load_error` | system | Lua errors with file, line and stack, warnings, scripts that fail to load, read from the console. |
| `script.warning`, `script.error` | script | `Siku.print.warn` and `Siku.print.error`. |
| `log.dropped`, `log.client_dropped` | system | Records lost to a full buffer or to the client limits. |
| `permissions.*`, `jobs.*`, `licenses.*`, `accounts.mutation`, `command.executed` | audit | The core's own sensitive operations. |

### Collection

The core keeps the encoded records in a bounded ring and serves them on `GET /siku_core/logs/pull?cursor=<seq>&limit=<n>` of FXServer's HTTP port; the cursor of a request acknowledges the previous one. Only loopback addresses may read, or a client presenting the `siku:logToken` convar as a bearer token. `GET /siku_core/logs/health` reports the boot id, the sequence, the buffer and the drops. The agent runs on the same host and polls every second.

Measured in a Lua 5.4 harness with FiveM stubs (not FXServer): a structured event with data and two entities costs about 15 µs to queue, a plain message 5 µs, a span 4 µs, a steady `state` call 0.2 µs; encoding happens later in the core, in batches.

## Database

`config/migration.lua` declares the core schema, applied on startup: `users`, `characters`, `roles`, `permissions`, `role_permissions`, `character_roles`, `rbac_audit_log`, for the job engine `jobs`, `job_grades`, `job_permissions`, `job_grade_permissions`, `job_memberships` and `job_audit_log`, for the accounts engine `accounts`, `account_access` and `account_mutations`, and for the licenses engine `licenses`, `license_holdings` and `license_audit_log`, with indexes and cascading foreign keys.

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
| `config/jobs.lua` | server, consumers | Domain limits (`maxJobs`, `maxOnDuty`, `false` for none), auditing. |
| `config/accounts.lua` | server, consumers | Negative balance policy, mutation journal, batch and amount limits. |
| `config/licenses.lua` | server, consumers | Auditing. |
| `config/log.lua` | server, client, consumers | Buffers, client limits, identifiers kept in session events, tracing and sampling, data limits. |

## Conventions

The ecosystem follows one naming scheme, enforced across resources:

- Events: `siku:<context>:<name>` for cross-resource contracts, `<resource>:<side>:<name>` internally.
- State bags: `siku:state:<name>`.
- Callbacks: `siku:callback:<name>`.

## Ecosystem

Resources built on this core: [`siku_chat`](https://github.com/siku-project/siku_chat), [`siku_notification`](https://github.com/siku-project/siku_notification), [`siku_progress`](https://github.com/siku-project/siku_progress), [`siku_inventory`](https://github.com/siku-project/siku_inventory), [`siku_multicharacter`](https://github.com/siku-project/siku_multicharacter), [`siku_status`](https://github.com/siku-project/siku_status), [`siku_hud`](https://github.com/siku-project/siku_hud) — started from [`Siku_Boilerplate`](https://github.com/siku-project/Siku_Boilerplate).

## Credits

Part of the [SIKU project](https://github.com/siku-project) — © Siku Studio.
