import json, struct, sys
import numpy as np
src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
clen = struct.unpack('<I', d[12:16])[0]
j = json.loads(d[20:20 + clen])
off = 20 + clen
blen = struct.unpack('<I', d[off:off + 4])[0]
buf = d[off + 8: off + 8 + blen]
def acc(i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a['componentType']]
    n = {'SCALAR': 1, 'VEC3': 3, 'VEC2': 2}[a['type']]
    return np.frombuffer(buf, dtype=dt, count=a['count'] * n, offset=start).reshape(-1, n) if n > 1 else np.frombuffer(buf, dtype=dt, count=a['count'], offset=start)
prim = j['meshes'][0]['primitives'][0]
P = acc(prim['attributes']['POSITION']).astype(np.float32)
I = acc(prim['indices']).astype(np.uint32).reshape(-1, 3)
# area-weighted vertex normals
v0, v1, v2 = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
fn = np.cross(v1 - v0, v2 - v0)
N = np.zeros_like(P)
for k in range(3):
    np.add.at(N, I[:, k], fn)
N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
# Most normals should point away from the centre if the winding is outward
c = P.mean(axis=0)
outward = np.mean(np.sum(N * (P - c), axis=1) > 0)
print('verts', len(P), 'tris', len(I), 'outward fraction', round(float(outward), 3))
np.save(out + '/P.npy', P); np.save(out + '/I.npy', I); np.save(out + '/N.npy', N.astype(np.float32))
P.astype('<f4').tofile(out + '/pos.bin'); N.astype('<f4').tofile(out + '/nrm.bin'); I.astype('<u4').tofile(out + '/idx.bin')
