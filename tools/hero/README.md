# Hero model pipeline

Turns the sculpted `MC_Peasant.glb` (untextured, one fused mesh) plus a front reference painting into `assets/hero/hero_mesh.res`. Not part of the game build. Needs Python 3 with numpy, scipy, Pillow and opencv, and Godot 4.4.

1. `python3 read_glb.py MC_Peasant.glb work` reads positions and indices into `work/P.npy`, `I.npy`, `N.npy` and raw `.bin` copies.
2. `HERO_WORK=$PWD/work godot --headless --path <project with decimate.gd> -s decimate.gd` writes simplified index lists `work/lod_N.bin`.
3. `python3 compact.py work 3 hi` keeps the 32k-triangle level as `work/P_hi.npy`, `I_hi.npy`, `N_hi.npy`.
4. `python3 segment.py reference.jpg work` stores the reference image as `work/img.npy`.
5. `python3 build_hero.py work out` warps the reference onto the front of the mesh (thin-plate spline on hand-placed landmarks), paints the back from colours sampled off the reference, cuts the arms away (the game animates its own arms), weights the rest to the body, head and leg bones, and writes `out/hero_*.bin`, `hero_front.png` and `hero_rig.json`.
6. From the project root: `HERO_DIR=$PWD/tools/hero/out godot --headless --path . -s tools/hero/assemble.gd` saves `assets/hero/hero_mesh.res`.

`scripts/hero_skin.gd` drives the mesh at runtime from the procedural rig in `scripts/player.gd`.
