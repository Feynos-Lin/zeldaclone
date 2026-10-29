# Weapon model pipeline

Builds `assets/items/{sword,bow,bomb}_mesh.res` from `starting_sword.glb`, `starting_bow.glb` and `handheld_bomb.glb` and their art:

1. `python3 ../hero/read_glb.py <model>.glb work`, `python3 ../hero/compact.py work full full`, `python3 ../hero/segment.py <art>.jpg work`
2. `python3 build_item.py sword|bow|bomb work out` projects the art straight through the object, moves the grip to the origin and turns it into the hero's hand space (sword blade along -Z, bow belly forward), and records the blade tip, string, or fuse tip.
3. `HERO_DIR=$PWD/out PREFIX=sculpt RES_OUT=res://assets/items/<name>_mesh.res godot --headless --path ../.. -s tools/hero/assemble.gd`
