"""Paint a weapon sculpt from its front-view art and put it in the hero's hand space.

Usage: build_item.py <sword|bow|bomb> <work dir> <out dir>
Inputs: work/P_full.npy, I_full.npy, N_full.npy (tools/hero/compact.py), work/img.npy and
work/img_mask.npy (tools/hero/segment.py). The art is projected straight through the
object, so both faces carry it; these props are close to symmetric front to back.
Outputs: sculpt_*.bin (no bones), sculpt_front.png, sculpt_rig.json with handy points.
"""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

CONFIGS = {
    # game = (x, -z, y - grip) * s : blade along -Z, crossguard along X, grip at the origin
    'sword': {'scale': 0.45, 'grip': (0.0, 0.68, 0.0), 'axes': 'blade'},
    # game = (z, y, -(x - grip)) * s : limbs up, belly forward (-Z), string toward the archer
    'bow': {'scale': 0.5, 'grip': (0.15, 0.0, 0.0), 'axes': 'bow'},
    # as modelled, centred on the ball
    'bomb': {'scale': 0.22, 'grip': (0.0, -0.376, 0.0), 'axes': 'same'},
}
NAME, W, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
C = CONFIGS[NAME]
P = np.load(W + '/P_full.npy').astype(np.float64)
I = np.load(W + '/I_full.npy').astype(np.int64)
N = np.load(W + '/N_full.npy').astype(np.float64)
img = np.load(W + '/img.npy')
mask = np.load(W + '/img_mask.npy').astype(bool)
IH, IW, _ = img.shape
ys, xs = np.nonzero(mask)
bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
mn, mx = P.min(0), P.max(0)
px = bx0 + (P[:, 0] - mn[0]) / (mx[0] - mn[0]) * (bx1 - bx0)
py = by0 + (mx[1] - P[:, 1]) / (mx[1] - mn[1]) * (by1 - by0)
valid = ndi.binary_erosion(mask, iterations=2)
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
filled = img[idx[0], idx[1]]
pad = 6
X0, Y0, X1, Y1 = max(bx0 - pad, 0), max(by0 - pad, 0), min(bx1 + pad, IW), min(by1 + pad, IH)
crop = (np.clip(filled[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)
TW = 256 if (X1 - X0) < (Y1 - Y0) * 0.5 else 512
Image.fromarray(crop).resize((TW, 1024 if TW == 256 else 512), Image.LANCZOS).save(OUT + '/sculpt_front.png')
uv = np.stack([(px - X0) / (X1 - X0), (py - Y0) / (Y1 - Y0)], 1)
pxi = np.clip(np.stack([px, py], 1).round().astype(int), 0, [IW - 1, IH - 1])
back = filled[pxi[:, 1], pxi[:, 0]]
col = np.concatenate([back, np.ones((len(P), 1))], 1).astype(np.float32)   # front art everywhere

s = C['scale']; g = np.array(C['grip'])
Q = P - g
if C['axes'] == 'blade':
    G = np.stack([Q[:, 0], -Q[:, 2], Q[:, 1]], 1) * s
    Ng = np.stack([N[:, 0], -N[:, 2], N[:, 1]], 1)
    tip = np.array([0.0, 0.0, (mn[1] - g[1]) * s])
    extra = {'tip': tip.tolist(), 'length': float((mx[1] - mn[1]) * s)}
elif C['axes'] == 'bow':
    G = np.stack([Q[:, 2], Q[:, 1], -Q[:, 0]], 1) * s
    Ng = np.stack([N[:, 2], N[:, 1], -N[:, 0]], 1)
    string_x = mn[0]
    extra = {'string_z': float(-(string_x - g[0]) * s), 'top': float((mx[1] - g[1]) * s), 'bottom': float((mn[1] - g[1]) * s)}
else:
    G = Q * s
    Ng = N
    top = P[np.argmax(P[:, 1])] - g
    extra = {'fuse_tip': (top * s).tolist(), 'radius': float(np.max(np.abs(P[P[:, 1] < 0.25] - g)[:, [0, 2]]) * s)}
rig = {'scale': s, 'bones': [], 'item': NAME}
rig.update(extra)
json.dump(rig, open(OUT + '/sculpt_rig.json', 'w'), indent=1)
G.astype('<f4').tofile(OUT + '/sculpt_pos.bin'); Ng.astype('<f4').tofile(OUT + '/sculpt_nrm.bin')
uv.astype('<f4').tofile(OUT + '/sculpt_uv.bin'); col.tofile(OUT + '/sculpt_col.bin')
I.astype('<i4').tofile(OUT + '/sculpt_idx.bin')
print(NAME, 'verts', len(P), 'tris', len(I), 'size', (G.max(0) - G.min(0)).round(3), extra)
