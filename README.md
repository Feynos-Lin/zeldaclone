# Wrenmoor

An N64-style action adventure prototype built with Godot 4.4. It runs natively on Android and on Fedora/Linux.

You start in Wrenmoor, a village in a forest clearing, at dusk. Past the glowing ward-stones a trail winds through the woods to Hollow Cave, where the dead keep crawling out. More of them come at night.

## Install

Every push to `main` builds a new release (see the Releases page):

- **Android:** download the `.apk` and open it (allow installs from your browser or file manager when asked).
- **Fedora:** `sudo dnf install ./wrenmoor-*.rpm`, then launch Wrenmoor from the app menu or run `wrenmoor`.
- **Other Linux:** extract the `.tar.gz` and run `./wrenmoor`.

## Controls

| | Keyboard / mouse | Controller (Xbox names) | Touch |
|---|---|---|---|
| Move | WASD | Left stick or D-pad | Left-side stick |
| Sword (hold, then release to spin) | J / left click | X or B | B |
| Roll / talk / advance text | Space | A | A |
| Lock on | Tab / right click | LT or LB | Z |
| Turn / tilt camera | Q / E, R / F | Right stick | Drag on the right side |
| Recenter camera | C | Y or click right stick | |
| Pause menu | Esc / P | Start or Back | |
| Fullscreen | F11 | | |

### Controllers

Xbox-style (XInput) pads, PlayStation, Nintendo, and the DInput pads in Godot's built-in controller database work as soon as they're plugged in or paired, on Fedora and Android. Pads with an X/D mode switch work in either mode. On-screen prompts use your controller's own button names, and it rumbles when you're hit or land a strike.

If a controller isn't recognized or its buttons come out wrong, open the pause menu and choose **Controller setup**, then press each button as asked (anything you don't press within 8 seconds is skipped). The mapping is saved for that controller model. **Reset controller mapping** returns it to the default layout.

## What's in the prototype

- Forest village with no walls: thatched cottages, villagers to talk to, and a ring of ward-stones the dead can't cross
- A winding trail through the woods to a graveyard and Hollow Cave, which spawns zombies
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
