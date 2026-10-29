# Villager model pipeline

Builds `assets/villagers/lady_mesh.res` (Grandmother Ysel, `town_1_old_lady.glb`) and `assets/villagers/child_mesh.res` (Pip, `town_1_child.glb`) from the sculpts and their front-view art:

1. `python3 ../hero/read_glb.py <model>.glb work`, `python3 ../hero/compact.py work full full`, `python3 ../hero/segment.py <art>.jpg work`
2. `python3 build_npc.py lady|child work out` warps the art onto the front (landmarks per character in `CONFIGS`), paints the back (hair behind the face, the dress behind the apron), finds the arms by following them down from where they hang free, unzips the few triangles where a sleeve was fused to the body, and weights a small skeleton (fixed root for the legs, body, head, both arms).
3. `HERO_DIR=$PWD/out PREFIX=sculpt RES_OUT=res://assets/villagers/<name>_mesh.res godot --headless --path ../.. -s tools/hero/assemble.gd`
