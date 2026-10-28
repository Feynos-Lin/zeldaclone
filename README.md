# Wrenmoor

An N64-style action adventure prototype built with Godot 4.4. It runs natively on Android and on Fedora/Linux.

You start in the walled town of Wrenmoor at dusk. Past the gate and the glowing ward-stones lies the Hollow Field, and at its far end, Hollow Cave, where the dead keep crawling out. More of them come at night.

## Install

Every push to `main` builds a new release (see the Releases page):

- **Android:** download the `.apk` and open it (allow installs from your browser or file manager when asked).
- **Fedora:** `sudo dnf install ./wrenmoor-*.rpm`, then launch Wrenmoor from the app menu or run `wrenmoor`.
- **Other Linux:** extract the `.tar.gz` and run `./wrenmoor`.

## Controls

| | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Move | WASD | Left stick | Left-side stick |
| Sword (hold, then release to spin) | J / left click | X or B | B |
| Roll / talk / advance text | Space | A | A |
| Lock on / recenter camera | Tab / right click | LT or LB | Z |
| Turn camera | Q / E or arrow keys | Right stick | Drag on the right side |
| Fullscreen | F11 | | |

## What's in the prototype

- Town with villagers to talk to, a gate, ward-stones the dead can't cross
- Open field with trees, rocks and graves; cave that spawns zombies
- 3-hit sword combo, charged spin attack, dodge roll with invincibility, lock-on with letterbox bars
- Hearts, bone shards and heart drops, death and respawn
- Day/night clock (one in-game hour every 20 seconds); nights spawn more zombies and a big pale moon rises
- Low-res rendering, depth fog, vertex lighting and blob shadows for the N64 look
- All models, textures and sounds are generated in code, so there are no asset files

## Project layout

- `scripts/main.gd` builds the world, runs the clock, spawns zombies, handles dialog
- `scripts/player.gd`, `zombie.gd`, `npc.gd`, `pickup.gd` are the characters and items
- `scripts/camera_rig.gd`, `hud.gd`, `touch_controls.gd`, `sfx.gd` handle the camera, UI, phone controls and sound
- `scripts/build.gd` has the low-poly mesh, texture and material helpers
- `.github/workflows/build.yml` exports the APK and Linux build and packages the `.rpm`

`android/debug.keystore` is a throwaway signing key kept in the repo so each new APK installs over the previous one. Use your own key before publishing anywhere.
