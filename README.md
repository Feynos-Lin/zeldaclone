# Wrenmoor

A stylized, GameCube-era-looking action adventure prototype built with Godot 4.4. It runs natively on Android and on Fedora/Linux.

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
| Jump (or talk, next to someone) | Space | Y | J |
| Roll / talk / advance text | Shift / K / Enter | A | A |
| Shield (hold) | L / Ctrl / right click | RT | R |
| Use item: bow (hold to draw, release to shoot) or bomb (press to light, again to throw) | I | RB | I |
| Change item | O / mouse wheel | LB | + |
| Lock on (the bow aims at the locked-on zombie) | Tab / middle click | LT | Z |
| Turn / tilt camera | Q / E, R / F | Right stick | Drag on the right side |
| Recenter camera | C | Click right stick | |
| Pause menu | Esc / P | Start or Back | |
| Fullscreen | F11 | | |

### Graphics settings

Press Start or Esc for the pause menu, then use left and right on an option to change it:

- **Graphics:** Low (no shadows or bloom, shorter draw distance), Medium (sun shadows, bloom; the default on Android) or High (2x anti-aliasing, longer shadows, denser grass; the default on desktop).
- **Resolution (desktop):** Native, or 1280x720 to 2560x1440 (16:9), 1280x800 to 1920x1200 (16:10), 1024x768 to 1920x1440 (4:3), 1280x1024 (5:4), 2560x1080 and 3440x1440 (21:9). In fullscreen a ratio that doesn't match your monitor gets black bars, and sizes above your screen are rendered sharper and scaled down.
- **Resolution (Android):** the 3D render resolution: 480p, 720p (default), 1080p, 1440p or Native.
- **Display (desktop):** Windowed or Fullscreen (F11 also toggles it).

Settings are saved on the device.

### Controllers

Xbox-style (XInput) pads, PlayStation, Nintendo, and the DInput pads in Godot's built-in controller database work as soon as they're plugged in or paired, on Fedora and Android. Pads with an X/D mode switch work in either mode. On-screen prompts use your controller's own button names, and it rumbles when you're hit or land a strike.

If a controller isn't recognized or its buttons come out wrong, open the pause menu and choose **Controller setup**, then press each button as asked (anything you don't press within 8 seconds is skipped). The mapping is saved for that controller model. **Reset controller mapping** returns it to the default layout.

## What's in the prototype

- Forest village with no walls: thatched cottages, villagers to talk to, and a ring of ward-stones the dead can't cross
- A winding trail through the woods to a graveyard and Hollow Cave, which spawns zombies
- 3-hit sword combo, charged spin attack, dodge roll with invincibility, jumping, lock-on with letterbox bars
- Hold the shield up to sidestep and block blows from the front; blocked zombies reel back
- Bow and arrows (a full draw hits twice as hard) and bombs that bounce, roll and blow up after a few seconds; zombies drop arrow bundles and bombs
- Grandmother Ysel nods and gestures as she talks, and Pip bounces and waves
- Old Brannoc, the gate guard, stamps his spear while he talks to you
- Hearts, bone shards and heart drops, death and respawn
- Day/night clock (one in-game hour every 20 seconds); nights spawn more zombies and a big pale moon rises
- Hand-painted look: soft per-pixel lighting, real sun shadows, sky, bloom and film-style grading
- Pause menu settings: Graphics (Low / Medium / High), Resolution (up to 1440p in 16:9, 16:10, 4:3, 5:4 and 21:9 on desktop; render resolution on Android) and Windowed / Fullscreen
- The hero, the villagers, the gate guard, the sword, bow and bombs are sculpted models painted from their art; the rest (world, zombies, sounds) is generated in code

## Project layout

- `scripts/main.gd` builds the world, runs the clock, spawns zombies, handles dialog
- `scripts/player.gd`, `zombie.gd`, `npc.gd`, `pickup.gd` are the characters and items
- `scripts/camera_rig.gd`, `hud.gd`, `touch_controls.gd`, `sfx.gd` handle the camera, UI, phone controls and sound
- `scripts/build.gd` has the low-poly mesh, texture and material helpers
- `scripts/hero_skin.gd` and `assets/hero/` are the hero's sculpted model; `scripts/sculpt_rig.gd` and `assets/guard/` the guard's; `tools/hero/`, `tools/guard/`, `tools/npc/` and `tools/items/` rebuild them from the source sculpts (`assets/villagers/`, `assets/items/`)
- `.github/workflows/build.yml` exports the APK and Linux build and packages the `.rpm`

`android/debug.keystore` is a throwaway signing key kept in the repo so each new APK installs over the previous one. Use your own key before publishing anywhere.
