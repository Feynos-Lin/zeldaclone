import sys, numpy as np
W = sys.argv[1]; tag = sys.argv[3]
lod = sys.argv[2]   # LOD number from decimate.gd, or 'full' for the original triangles
P = np.load(W + '/P.npy')
if lod == 'full':
    li = np.load(W + '/I.npy')[:, [0, 2, 1]].astype(np.int64)   # glTF is counter-clockwise; Godot wants clockwise
else:
    li = np.fromfile(W + '/lod_%s.bin' % lod, dtype='<i4').reshape(-1, 3)   # already clockwise (Godot)
used = np.unique(li)
remap = -np.ones(len(P), dtype=np.int64); remap[used] = np.arange(len(used))
Pc = P[used]; Ic = remap[li]
# recompute smooth normals on the simplified mesh (clockwise winding -> flip cross)
v0, v1, v2 = Pc[Ic[:, 0]], Pc[Ic[:, 1]], Pc[Ic[:, 2]]
fn = -np.cross(v1 - v0, v2 - v0)
N = np.zeros_like(Pc)
for k in range(3): np.add.at(N, Ic[:, k], fn)
N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
np.save(W + f'/P_{tag}.npy', Pc); np.save(W + f'/I_{tag}.npy', Ic); np.save(W + f'/N_{tag}.npy', N.astype(np.float32))
Pc.astype('<f4').tofile(W + f'/pos_{tag}.bin'); N.astype('<f4').tofile(W + f'/nrm_{tag}.bin'); Ic.astype('<u4').tofile(W + f'/idx_{tag}.bin')
print(tag, 'verts', len(Pc), 'tris', len(Ic))
