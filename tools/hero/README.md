# Hero model pipeline

Turns the sculpted `MC_Peasant.glb` (untextured, one mesh, standing with arms loose at its sides) plus a front reference painting into `assets/hero/hero_mesh.res`. Not part of the game build. Needs Python 3 with numpy, scipy, Pillow and opencv, and Godot 4.4.

1. `python3 read_glb.py MC_Peasant.glb work` reads positions and indices into `work/P.npy`, `I.npy`, `N.npy` and raw `.bin` copies.
2. `HERO_WORK=$PWD/work godot --headless --path <project with decimate.gd> -s decimate.gd` writes simplified index lists `work/lod_N.bin`.
3. `python3 compact.py work full full` keeps every original triangle as `work/P_full.npy`, `I_full.npy`, `N_full.npy` (the game uses this). `python3 compact.py work 3 hi` makes a 32k-triangle version from a decimated level instead.
4. `python3 segment.py reference.jpg work` (the landmarks in `build_hero.py` are placed for the current front-view art) stores the reference image as `work/img.npy`.
5. `python3 build_hero.py work out full` warps the reference onto the front of the mesh (thin-plate spline on hand-placed landmarks), paints the back from colours sampled off the reference, finds the arms slice by slice, weights everything to the body, head, arm and leg bones, and writes `out/hero_*.bin`, `hero_front.png` and `hero_rig.json`.
6. From the project root: `HERO_DIR=$PWD/tools/hero/out godot --headless --path . -s tools/hero/assemble.gd` saves `assets/hero/hero_mesh.res`.

`scripts/hero_skin.gd` drives the mesh at runtime from the procedural rig in `scripts/player.gd`.
