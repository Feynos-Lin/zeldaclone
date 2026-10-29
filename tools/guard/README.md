# Gate guard model pipeline

Builds `assets/guard/guard_mesh.res` from `Town_1_Guard.glb` and its character art, reusing the hero tools:

1. `python3 ../hero/read_glb.py Town_1_Guard.glb work`
2. `python3 ../hero/compact.py work full full`
3. `python3 ../hero/segment.py guard_art.jpg work`
4. `python3 build_guard.py work out` drops the loose specks, warps the art onto the front, paints the back from the same colours (helmet steel where the face is, plain tabard behind the emblem, the spear and sheath in wood), and weights the sculpt to a small skeleton: a fixed root for the legs, body, head, both arms, with the spear riding on the left forearm.
5. From the project root: `HERO_DIR=$PWD/tools/guard/out PREFIX=sculpt RES_OUT=res://assets/guard/guard_mesh.res godot --headless --path . -s tools/hero/assemble.gd`

`scripts/sculpt_rig.gd` poses it at runtime; `scripts/npc.gd` animates the idle and the spear stamp.
