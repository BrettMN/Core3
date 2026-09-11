# Village GM commands

How to inspect and change the Force Sensitive village phase on a development
server.

## Requirements

- `jediProgressionType = VILLAGEJEDIPROGRESSION` in
  [../../managers/jedi/jedi_manager.lua](../../managers/jedi/jedi_manager.lua).
  Every command below returns a generic error on any other progression type.
- An account with `admin_level = 15`. Set it after the account exists:
  ```sql
  update accounts set admin_level=15 where username='YOURNAME';
  ```
  Relog for it to take effect.

## The GM panel

In-game:

```
/gmFsVillage
```

Opens the Village GM Panel, which shows:

- Current phase and phase ID
- Current server time
- Next phase change time
- Phase time left
- Number of players currently in the village

Menu options:

| Option | What it does |
| --- | --- |
| Change to next phase | Advances one phase, wrapping 4 to 1 |
| Lookup player by target / name / oid | Inspect one player's village progress |
| List players in village | Online players inside the village |
| Manage CounterStrike Bases | Phase 3 only |
| Show Light / Dark Council Ranks | FRS council standing |
| Output LUA os.time() | Prints the server's Lua clock, for debugging timers |

### Changing the phase resets progress

"Change to next phase" warns before acting, and the warning is accurate: it
resets the current-phase progress of every player in that phase. It is the same
code path as the scheduled timer, so it is not a soft preview.

### "Change to next phase" is missing

The option is gated on `productionServer` in
[village_gm_sui.lua](village_gm_sui.lua):

```lua
VillageGmSui = ScreenPlay:new {
	productionServer = false
}
```

It must be `false` for the option to appear. Leave it `true` on a live server.

## From the server console

Attach to the running server:

```powershell
docker exec -it swgemu-core3 su - swgemu -c 'screen -D -RR swgemu-server'
```

At the `>` prompt, advance one phase:

```
runLuaFunction VillageJediManagerTownship:switchToNextPhase
```

`runLuaFunction` takes `{module}:{function}` and passes no arguments, so it can
only call the no-argument form. Calling `switchToNextPhase` without
`manualSwitch` still advances the phase; it just takes the scheduled-change code
path rather than the manual one.

Detach with `Ctrl-A D`. Do not use `Ctrl-C` -- that signals the server.

## Jumping to a specific phase

Neither the panel nor the console can jump straight to phase 3; both only step
forward. To land on a specific phase, either use "Change to next phase"
repeatedly, or shorten the duration (below) and let the timer run.

## Phase duration

Set in [village_jedi_manager_township.lua:12](village_jedi_manager_township.lua#L12),
in milliseconds:

```lua
VILLAGE_PHASE_DURATION = 1 * 24 * 60 * 60 * 1000 -- 1 day
```

With 4 phases, that is a 4-day full cycle. Stock Core3 ships `3 * 7 * 24 * 60 *
60 * 1000` (3 weeks, a 12-week cycle).

Three things to know when changing it:

1. **Phase changes land at 18:00 server time**, not at the exact interval, set
   by `phaseChangeTimeOfDay` on
   [line 10](village_jedi_manager_township.lua#L10). The container runs
   `TZ=Etc/UTC`, so that is 18:00 UTC. Comment the line out to change exactly on
   the interval.
2. **Durations under 24 hours ignore that setting** and log a notice
   ([line 65](village_jedi_manager_township.lua#L65)). Exactly 24 hours does
   *not* qualify -- the check is `< 24h` -- so a 1-day duration still snaps to
   18:00.
3. **The pending change is a persisted server event** (`VillagePhaseChange`).
   [Lines 17-33](village_jedi_manager_township.lua#L17) only reschedule when no
   event exists or when the remaining time exceeds the new duration. So
   *shortening* the duration reschedules on the next restart, but *lengthening*
   it leaves the existing deadline alone. Force a reschedule with
   "Change to next phase".

This is Lua, so no rebuild is needed -- but the container builds from a git
clone, so commit on the host, run `sync` in the container, then restart the
server.

## Related GM commands

| Command | Purpose |
| --- | --- |
| `/gmJediState` | Read or set a player's Jedi state |
| `/resetJedi` | Reset a player's Jedi progression |
| `/checkForceStatus` | Player-facing; village routes it to the Glowing check |

See [../../commands/](../../commands/) for the full set.
