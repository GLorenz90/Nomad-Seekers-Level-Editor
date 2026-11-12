# Nomad's Seekers level format (version 1)

The contract between the game and the level editor (Part 13a). The editor
writes this format and the game builds levels from it. The code that reads,
writes and checks it is `addons/seeker_data/level_data.gd` (`LevelData`). It
doesn't depend on the game's classes, so the editor can use the same file.

The worked example is `levels/test_1/demo/`, written by
`tools/build_demo_level.gd`. It uses something from every layer, and
`tests/level_test.gd` plays it.

## Folders, areas and sessions

```
levels/
  forest_1/            one folder per area (Grayson, 2026-11-12)
    glade/             a level
    ravine/            another level
  forest_2/
  forest_boss/         boss areas get their own folder too
quests/
  some_quest.json      quests made in the editor (see Quests)
```

- A teleporter, quest or menu can send a Seeker to **`area:forest_1`**. The
  game picks one level from that folder the first time it's needed in a
  session, and keeps that pick until the player quits to the title
  (`Maps.pick`, `Maps.new_session`). In co-op everyone shares the same picks.
- A destination can also be a level folder (`res://levels/forest_1/glade`), a
  scene (`res://scenes/arena.tscn`) or `hub` (Nomad-2).
- `user://levels/` holds your own levels (and the workshop's, later). They can
  be played from the Debug tab but never join the area rotation.
- **Playtest:** run the game with `-- --level=<folder>` to go straight into a
  level with the last played character, skipping the title screen.
- **Exports:** levels are plain files, so an export preset must include
  `levels/*` and `quests/*` in its non-resource include filter.

## A level

```
my_level/
  level.json        meta
  map.json          Layer 1: Map
  interaction.json  Layer 2: Interaction
  combat.json       Layer 3: Combat
  assets/           glb / gltf models (and their textures)
```

Each layer is its own file, so the editor can switch between layers freely.
**A level never holds code.** Godot `.tres` / `.tscn` files can carry scripts
that run when they're loaded, so levels use only JSON and plain assets. The
game builds a level only from its own whitelisted pieces, and models load
through `GLTFDocument`, which can't carry scripts.

Shared conventions:
- **Positions** are `[x, y, z]` in metres, in world space. `y = 0` is the
  usual floor height and -Z is "north".
- **Rotation** is either `"yaw"` (degrees around Y) or `"rot": [x, y, z]`
  (degrees). `"scale": [x, y, z]` is optional.
- **Colors** are `[r, g, b]` or `[r, g, b, a]`, from 0 to 1.
- **Every** room, piece, wall, decoration, object, button group, dialogue and
  enemy has an `"id"` that is unique across the whole level. The layers refer
  to each other only by id.

### level.json

```json
{"format": 1, "name": "Glade", "size": "small", "area": "forest_1",
 "author": "", "description": ""}
```

`size` is one of the following (Grayson, 2026-11-12). Only rooms count;
corridors never do.

| size | rooms |
|---|---|
| `arena` | 1, and no corridors |
| `small` | 5–9 |
| `medium` | 10–14 |
| `large` | 15–19 |
| `huge` | 20–25 |

### map.json (Layer 1: Map)

```json
{
  "grid": 4.0,
  "lighting": {"preset": "dusk", "sun_energy": 1.0, "ambient_energy": 1.0,
               "exposure": 1.0, "fog_density": 0.0, "sun_angle": [-50, 35], "tint": [1, 1, 1]},
  "start": {"pos": [0, 0.1, 4], "yaw": 0},
  "assets": [{"id": "rock_big", "file": "assets/rock_big.glb", "license": "CC0", "author": "Kenney"}],
  "rooms": [{"id": "room_1", "kind": "room", "name": "Landing", "pos": [0, 0, 0], "size": [16, 6, 16]}],
  "pieces": [{"id": "floor_1", "asset": "builtin:box", "pos": [0, -1, 0], "size": [16, 1, 16],
              "color": [0.4, 0.45, 0.4], "collision": "box"}],
  "walls": [{"id": "pen", "pos": [-6, 0, -30], "size": [0.4, 2, 4], "yaw": 0, "blocks": "seekers"}],
  "decorations": [{"id": "tree_1", "asset": "tree", "pos": [3, 0, 2], "collision": "none",
                   "animation": {"preset": "sway", "amount": 1.0, "speed": 1.0}}]
}
```

- **grid**: rooms and corridors snap to 4 m. Pieces and decorations can go
  anywhere.
- **lighting**: `preset` is one of `day`, `dusk`, `overcast`, `night`,
  `cave`, `interior`. The game clamps each slider: `sun_energy` 0.3–1.6,
  `ambient_energy` 0.5–1.5, `exposure` 0.8–1.3, `fog_density` 0–0.03. The
  tint is held to 0.6–1 per channel, and the sun stays 10–90° up. A room
  meant to be dark uses the Darkness hazard instead.
- **rooms**: `kind` is `room` or `corridor`. `pos` is the bottom centre of
  the room's box. A room's box is its room area: combat starts there, and the
  Trap Scanner reveals traps inside it.
- **assets**: imported models. `file` must be inside the level folder and end
  in `.glb` or `.gltf`. Each asset needs a `license` before it can be
  published.
- **pieces**: the map's solid parts. `asset` is an asset id, or one of
  `builtin:box`, `builtin:cylinder` or `builtin:ramp` (each takes `size` and
  `color`). `collision` is `none`, `box` (the model's bounds) or `mesh` (its
  triangles). The default is `box` for built-in shapes, and `mesh` for ramps
  and imported models. The navmesh is baked from anything with collision.
- **walls**: invisible walls. `blocks` is `all`, which also shapes the
  navmesh, or `seekers`, which uses physics layer 5: enemies walk through it,
  so it can keep players in an arena while enemies still come in.
- **decorations**: anything that doesn't interact. `collision` defaults to
  `none` (a rock with `box` collision blocks movement and the navmesh).
  Built-in decorations: `builtin:fireflies` (`size`, `amount`, `color`),
  `builtin:light` (`color`, `energy` 0–3, `range` 1–20 m),
  `builtin:searchlight` (sweeps by default), plus the built-in shapes.
  Animation presets are `sway`, `bob`, `spin`, `pulse` and `sweep`, with
  `amount` 0–2 and `speed` 0.1–4.

### interaction.json (Layer 2: Interaction)

```json
{
  "objects": [ ... ],
  "button_groups": [{"id": "plates", "buttons": ["plate_a", "plate_b"], "once": true}],
  "dialogues": [{"id": "intro", "lines": [{"speaker": "Commander Brandt", "text": "..."}],
                 "choices": [{"id": "yes", "text": "On my way."}]}],
  "flags": {"lever_pulled": false},
  "rules": [ ... ]
}
```

**Objects** (`"type"`; every object takes `id`, `pos` and `yaw`/`rot`):

| type | fields | wiring actions it takes |
|---|---|---|
| `door` | `size` [4.2, 4, 0.6], `start` `open`/`closed`, `label`, `open_when_cleared` (room id), `shut_during_combat` (room id) | `open`, `close`, `toggle` |
| `teleporter` | `destination` (see Folders), `label`, `requires_clear` (every room cleared), `dormant` (asleep until woken) | `wake`, `disable`, `toggle` |
| `lumidium_depot` | — | — |
| `lumidium_node` | `color` (`fire`…`raw`), `yield` 1–10 | — |
| `box` | `contents`: `random`, `oro` or a consumable id | — |
| `trap` | `kind`: `damage`, `slow`, `shock`, `poison`, `confuse`, `freeze`, `stun` | `disable` |
| `button` | `mode` `press`/`floor` | — |
| `hazard` | `kind` `poison_mist`/`darkness`, `active`, `zones`: [{`pos`, `size`}] in world space | `enable`, `disable`, `toggle` |
| `trigger_zone` | `size`, `once` (default true), `whole_party` (waits for every Seeker on the map), `enabled` | `enable`, `disable` |
| `platform` | `points` (world positions of its top; ≥ 2), `size`, `mode` `loop`/`ping_pong`/`step`, `speed` 0.5–8 m/s, `wait` s, `running`, `color` | `start`, `stop`, `toggle`, `step` |
| `bridge` | `length` 1–64, `width`, `extended`, `speed`; it slides out along its forward (-Z) | `extend`, `retract`, `toggle` |

- **Door shortcuts**: `open_when_cleared` opens the door when that room's
  combat ends. `shut_during_combat` closes it while that room fights, then
  opens it again. Anything else is done with rules.
- **Buttons**: a group fires when all of its buttons are down. With fewer
  Seekers than floor plates, extra plates latch (Part 11's rule). A button
  that isn't in a group is a group of one.
- **Platforms** carry Seekers; for now enemies don't ride them. **Bridges**
  connect the navmesh with a NavigationLink3D that only works while the
  bridge is fully out.
- **Rooms with combat** take `start_combat`.

**Rules** say: when an event happens, if the conditions hold, do the actions.

```json
{"id": "r1",
 "when": {"event": "combat_ended", "source": "room_2"},
 "if": [{"check": "flag", "flag": "lever_pulled", "is": true}],
 "do": [{"action": "open", "target": "door_3"},
        {"action": "wait", "seconds": 1.5},
        {"action": "start_dialogue", "target": "brandt_call"}],
 "once": true}
```

| event | source | value (optional match) |
|---|---|---|
| `level_started` | — | |
| `entered` | trigger zone id | |
| `party_present` | trigger zone id (`whole_party`) | |
| `pressed` | button group id, or a lone button's id | |
| `combat_started` | room id | |
| `wave_cleared` | room id | wave number (1 = first) |
| `combat_ended` | room id | |
| `enemy_defeated` | enemy placement id | |
| `health_below` | enemy placement id | percent: fires once HP is at or below it |
| `dialogue_ended` | dialogue id | choice id |
| `box_broken` | box id | |
| `node_broken` | Lumidium node id | |
| `timer_done` | timer id | |
| `flag_set` | flag name | |

Conditions (`"check"`): `flag` (`flag`, `is`); `difficulty_at_least`
(`value`: `normal`, `hard`, `very_hard`, `ultimate`; tiers aren't built yet,
so this is always `normal`); `party_at_least` (`value`: Seekers on the map);
`quest_active` (`value`: quest id).

Actions (`"action"`): the object actions in the table above (with
`target`), plus:
- `start_dialogue` (`target`: dialogue id). Dialogues play one at a time; a
  second one waits its turn.
- `set_flag` (`flag`, `value`)
- `start_timer` (`id`, `seconds`)
- `give_item` (`item`: `oro`, a consumable id, or `lumidium` with `color`;
  `amount`). It drops at each Seeker's feet.
- `complete_objective` (`key`: completes an `event` quest with that key)
- `banner` (`text`)
- `wait` (`seconds`; holds back the rest of the rule's actions)

Rules run once by default (`"once": false` repeats them).

### combat.json (Layer 3: Combat)

```json
{
  "rooms": [{"room": "room_2", "start": "enter", "start_delay": 0.8, "wave_delay": 1.0,
             "waves": [{"enemies": [ {placement}, ... ]}, ...]}],
  "free": [ {placement}, ... ]
}
```

- `start`: `enter` starts the fight when a Seeker walks in. `event` leaves it
  to the wiring (`start_combat`), for example after a button or a
  dialogue.
- Each wave starts when the previous wave's last enemy dies. When no waves
  are left, the room reports `combat_ended`.
- `free`: enemies outside waves, such as in corridors. They're there when the
  level loads, don't respawn and lock no doors.

A **placement**:

```json
{"id": "hound_1", "enemy": "grub_hound", "pos": [0, 0, -12], "yaw": 180,
 "spawn_delay": 0.5,
 "wander": true, "wander_radius": 3.0,
 "limited_chase": true, "chase_radius": 10.0,
 "aggro": "normal", "alert": false}
```

- `enemy`: a file name from `data/enemies/` (`grub_hound`, `mutated_crawler`,
  `sentry_drone`, `umbral_eye`, `caustic_ooze`, `lumen_sprite`). A level
  can't change an enemy's stats or attacks.
- `spawn_delay`: seconds after its wave starts (decimals allowed).
- `wander` + `wander_radius`: idles by wandering within that distance of its
  spawn point. Otherwise it stands still.
- `limited_chase` + `chase_radius`: gives up once its target is farther than
  that from its spawn point, walks home without healing, and can be pulled
  again once it's back.
- **Invalid:** both on with `chase_radius` < `wander_radius`. The publish
  check refuses it, and the game uses the wander radius for both.
- `aggro`: `short` (×0.6), `normal`, `long` (×1.5) of the enemy's own range.
- `alert`: comes straight for the Seekers when it appears. Defaults to true
  in waves (like PSO) and false in `free`.

## Quests

`quests/*.json` holds one quest, or a list of quests, listed at the Guild
after the built-in ones:

```json
{"id": "demo_run", "title": "Demo Run", "client": "...", "text": "...",
 "objective": "event", "key": "demo_boss", "goal": "Beat the boss.",
 "count": 1, "scene": "area:test_1", "place": "The demo level", "reward": 500}
```

`objective` is one of the following:
- `clear`: every wave room in `scene`
- `defeat`: `enemy` × `count`
- `bank_lumidium`: `count`
- `event`: a level rule runs `complete_objective` with this `key`

## The publish check

`LevelData.validate(Enemy.known_ids())` lists the problems that block
publishing:
- the room count doesn't fit the size, or an Arena has corridors
- there's no start, or no exit (a teleporter with a destination)
- an id is missing or used twice
- something points at an id that doesn't exist
- an asset has no license, or a piece or decoration uses an asset that isn't
  imported
- an object type, event, condition or action is unknown
- a combat room has no waves, or an empty wave
- an enemy is invalid, or is one the game doesn't have

Reachability (every room reachable, a way out of every combat room) needs
the navmesh, so the editor checks it.
