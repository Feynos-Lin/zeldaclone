"""Texture and rig the village guard sculpt (Town_1_Guard.glb) for the game.

Usage: build_guard.py <work dir> <out dir>
Inputs (glTF space: +Y up, faces +Z, his right is -X):
  work/P_full.npy, I_full.npy, N_full.npy   mesh from tools/hero/compact.py (Godot clockwise winding)
  work/img.npy                               reference painting from tools/hero/segment.py
Outputs (game model space: faces -Z, his right is +X, feet at y=0):
  sculpt_*.bin arrays, sculpt_front.png, sculpt_rig.json

The guard never walks, so his legs stay on a fixed root bone. The spear is
part of the sculpt and is skinned to his left forearm, so it moves with the
hand when he stamps it.
"""
import json, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.interpolate import RBFInterpolator
from scipy import ndimage as ndi
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

W = sys.argv[1]
OUT = sys.argv[2]
P = np.load(W + '/P_full.npy').astype(np.float64)
I = np.load(W + '/I_full.npy').astype(np.int64)
N = np.load(W + '/N_full.npy').astype(np.float64)
img = np.load(W + '/img.npy')
IH, IW, _ = img.shape

# ---------------------------------------------------------------- keep the figure, drop floating specks
e3 = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
A = coo_matrix((np.ones(len(e3)), (e3[:, 0], e3[:, 1])), shape=(len(P), len(P)))
nc, lab = connected_components(A, directed=False)
keep = lab == np.argmax(np.bincount(lab))
tri_keep = keep[I].all(1)
used = np.zeros(len(P), bool); used[I[tri_keep].ravel()] = True
remap = -np.ones(len(P), int); remap[used] = np.arange(used.sum())
P, N = P[used], N[used]
I = remap[I[tri_keep]]
print('kept verts', len(P), 'tris', len(I), 'dropped pieces', nc - 1)
x, y, z = P[:, 0], P[:, 1], P[:, 2]
DENS = max(1.0, (len(I) / 32768) ** 0.5)
e_all = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
_e1 = np.concatenate([e_all, e_all[:, ::-1]])
Adj = coo_matrix((np.ones(len(_e1)), (_e1[:, 0], _e1[:, 1])), shape=(len(P), len(P))).tocsr()
deg = np.asarray(Adj.sum(1)).ravel() + 1

# ---------------------------------------------------------------- landmarks: mesh front (x, y) -> image (px, py)
LM = [
    ((-0.08, 0.98), (535, 40)),                                    # helmet top
    ((-0.33, 0.65), (455, 125)), ((0.17, 0.65), (600, 125)),       # helmet brim
    ((-0.17, 0.575), (517, 145)), ((0.01, 0.575), (562, 145)),     # eyes
    ((-0.08, 0.48), (545, 165)), ((-0.08, 0.40), (545, 185)),      # nose, mouth
    ((-0.08, 0.33), (545, 200)),                                   # chin
    ((-0.30, 0.50), (485, 160)), ((0.13, 0.50), (585, 160)),       # cheeks
    ((-0.08, 0.27), (537, 220)),                                   # collar
    ((-0.52, 0.20), (422, 235)), ((0.32, 0.20), (605, 235)),       # pauldrons
    ((-0.09, 0.04), (532, 272)),                                   # emblem
    ((-0.08, -0.13), (530, 312)),                                  # belt
    ((-0.47, -0.38), (430, 380)), ((-0.45, -0.47), (440, 395)),    # right hand, fingertips
    ((0.40, -0.13), (660, 310)),                                   # left hand on the spear
    ((0.65, 1.00), (725, 30)), ((0.09, -1.00), (600, 515)),        # spear tip and butt
    ((0.06, 0.07), (565, 275)), ((0.33, -0.78), (625, 455)),       # scabbard
    ((-0.32, -0.55), (475, 390)), ((0.16, -0.55), (582, 390)),     # tabard hem
    ((-0.33, -0.63), (482, 425)), ((0.12, -0.63), (572, 425)),     # knees
    ((-0.32, -0.97), (455, 515)), ((0.18, -0.97), (580, 507)),     # boots
]
src = np.array([a for a, b in LM]); dst = np.array([b for a, b in LM], dtype=np.float64)
warp = RBFInterpolator(src, dst, kernel='thin_plate_spline', smoothing=0.5)
pix = warp(P[:, :2])

# ---------------------------------------------------------------- front texture
X0, Y0, X1, Y1 = 395, 0, 745, 545
TW, TH = 512, 1024
sat = img.max(2) - img.min(2)
bright = img.mean(2)
# background: light grey, flat, connected to the border
bgish = (sat < 0.06) & (bright > 0.5)
_lab, _ = ndi.label(bgish)
_edge = np.unique(np.concatenate([_lab[0], _lab[-1], _lab[:, 0], _lab[:, -1]]))
bg = np.isin(_lab, _edge[_edge > 0])
sil = Image.new('L', (IW, IH), 0); d = ImageDraw.Draw(sil)
for t in I[N[I].mean(1)[:, 2] > 0][::2]:
    d.polygon([tuple(pix[t[0]]), tuple(pix[t[1]]), tuple(pix[t[2]])], fill=1)
sil = np.asarray(sil).astype(bool)
valid = ndi.binary_erosion(~bg, iterations=2)
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
filled = img[idx[0], idx[1]]
Image.fromarray((np.clip(filled[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)).resize((TW, TH), Image.LANCZOS).save(OUT + '/sculpt_front.png')
uv = np.stack([(pix[:, 0] - X0) / (X1 - X0), (pix[:, 1] - Y0) / (Y1 - Y0)], 1)

# ---------------------------------------------------------------- spear:  everything close to its shaft line, plus the wider blade at the top
sp_c = np.array([0.476, 0.379, 0.299]); sp_d = np.array([0.269, 0.961, 0.071]); sp_d /= np.linalg.norm(sp_d)
sp_dist = np.linalg.norm(np.cross(P - sp_c, sp_d), axis=1)
# below the hand, refit the shaft on its own (the sculpt's spear isn't perfectly straight)
cand = (sp_dist < 0.08) & (y < -0.25) & (y > -0.95)
lo_c = P[cand].mean(0); _, _, vt = np.linalg.svd(P[cand] - lo_c); lo_d = vt[0] / np.linalg.norm(vt[0])
for _ in range(3):
    dl = np.linalg.norm(np.cross(P - lo_c, lo_d), axis=1)
    cand = (dl < 0.04) & (y < -0.2) & (y > -0.98)
    lo_c = P[cand].mean(0); _, _, vt = np.linalg.svd(P[cand] - lo_c); lo_d = vt[0] / np.linalg.norm(vt[0])
lo_dist = np.linalg.norm(np.cross(P - lo_c, lo_d), axis=1)
print('lower shaft', lo_c.round(3), lo_d.round(3))
sp_dist = np.where(y < -0.15, lo_dist, sp_dist)
sp_r = np.where(y > 0.72, 0.1, np.where(y > -0.15, 0.055, np.where(y > -0.88, 0.056, 0.045)))
spear = (sp_dist < sp_r) & (x > -0.05)

# ---------------------------------------------------------------- painted back: the front colour at the same spot, re-classed
import colorsys
hsv = np.array([colorsys.rgb_to_hsv(*c) for c in img.reshape(-1, 3)[::1]]).reshape(IH, IW, 3)
H_, S_, V_ = hsv[..., 0], hsv[..., 1], hsv[..., 2]
fg = valid
purple = fg & (H_ > 0.72) & (H_ < 0.92) & (S_ > 0.2)
gold = fg & (H_ > 0.07) & (H_ < 0.17) & (S_ > 0.4) & (V_ > 0.6)
yy, xx = np.mgrid[0:IH, 0:IW]
face_box = (xx > 470) & (xx < 600) & (yy > 125) & (yy < 215)
skin = fg & face_box & (H_ > 0.0) & (H_ < 0.12) & (S_ > 0.18) & (V_ > 0.25)
steel = fg & (S_ < 0.16)
def med(m):
    return np.median(img[m], axis=0)
PURPLE = med(purple)
STEEL = np.clip(np.percentile(img[steel & (V_ > 0.35)], 88, axis=0) * 1.2, 0, 1)
print('purple', PURPLE.round(2), 'steel', STEEL.round(2), 'gold', med(gold).round(2))
# a smoothed colour map with the face painted as helmet steel and the emblem as plain tabard
cmap = filled.copy()
cmap[skin] = STEEL
cmap[gold] = PURPLE
cmap = ndi.median_filter(cmap, size=(7, 7, 1))
pxi = np.clip(pix.round().astype(int), 0, [IW - 1, IH - 1])
back = cmap[pxi[:, 1], pxi[:, 0]]
# steel parts: one even steel tone, keeping only broad light and shade
lum_b = back.mean(1); sat_b = back.max(1) - back.min(1)
steelish = sat_b < 0.08
back[steelish] = STEEL * np.clip(lum_b[steelish] / STEEL.mean(), 0.85, 1.12)[:, None]
# the spear is a few pixels wide in the painting: paint it outright
line = np.linspace(0, 1, 200)
lp = np.stack([660 + (600 - 660) * line, 330 + (510 - 330) * line], 1).round().astype(int)
shaft_px = img[lp[:, 1], lp[:, 0]]
SHAFT = np.median(shaft_px[(shaft_px.max(1) - shaft_px.min(1)) > 0.12], axis=0)
print('shaft', SHAFT.round(2))
back[spear] = SHAFT
# the sheathed sword hanging from the belt: wood, like the painting
sc_a = np.array([0.06, 0.07, 0.0]); sc_b = np.array([0.33, -0.78, 0.0])
ab = (sc_b - sc_a)[:2]; tt = np.clip(((P[:, :2] - sc_a[:2]) @ ab) / (ab @ ab), 0, 1)
sc_dist = np.linalg.norm(P[:, :2] - (sc_a[:2] + tt[:, None] * ab), axis=1)
zone_sc = (sc_dist < 0.07) & ~spear & (y < 0.02) & (z > -0.08)
scabbard = zone_sc & (y < -0.55) & (y > -0.8) & (z < 0.13) & (sc_dist < 0.04)
for _ in range(400):   # grow along the sheath, staying near its line
    nb = np.zeros(len(P), bool)
    nb[e_all[:, 1][scabbard[e_all[:, 0]]]] = True
    nb[e_all[:, 0][scabbard[e_all[:, 1]]]] = True
    nxt = scabbard | (nb & zone_sc)
    if nxt.sum() == scabbard.sum():
        break
    scabbard = nxt
back[scabbard] = SHAFT
print('scabbard verts', int(scabbard.sum()))
back[spear & (y > 0.7)] = STEEL * 1.15
# the shield slung on his back isn't in the painting
shield = (z < -0.2) & (y > -0.5) & (y < 0.35)
back[shield] = STEEL * 0.95
rng = np.random.default_rng(5)
noise = (np.sin(x * 37) * np.sin(y * 29 + 1) * np.sin(z * 31 + 2)) * 0.05 + rng.normal(0, 0.015, len(P))
back = np.clip(back * 1.25 * (1 + noise[:, None]), 0, 1)
back[spear] = np.clip(np.where((y[spear] > 0.7)[:, None], STEEL * 1.15, SHAFT * 1.15), 0, 1)
back[scabbard] = np.clip(SHAFT * 1.15, 0, 1)
wf = np.clip((N[:, 2] + 0.12) / 0.42, 0, 1)
wf = wf * wf * (3 - 2 * wf)
inside = ndi.binary_erosion(valid, iterations=2)[pxi[:, 1], pxi[:, 0]]
wf = np.where(inside, wf, 0.0)
wf[shield] = 0.0
wf[spear] = 0.0
wf[scabbard] = 0.0

# ---------------------------------------------------------------- skeleton and weights
J = {
    'root': np.array([-0.08, -1.0, 0.0]),
    'body': np.array([-0.08, -0.4, 0.0]),
    'head': np.array([-0.08, 0.28, 0.0]),
    'arm_r': np.array([-0.38, 0.12, 0.0]), 'forearm_r': np.array([-0.44, -0.12, 0.0]),
    'arm_l': np.array([0.2, 0.12, 0.0]), 'forearm_l': np.array([0.27, -0.03, 0.02]),
}
BONES = ['root', 'body', 'head', 'arm_l', 'forearm_l', 'arm_r', 'forearm_r']
PARENT = {'root': None, 'body': 'root', 'head': 'body', 'arm_l': 'body', 'forearm_l': 'arm_l', 'arm_r': 'body', 'forearm_r': 'arm_r'}
BI = {b: i for i, b in enumerate(BONES)}
nv = len(P)
Wt = np.zeros((nv, len(BONES)))

# arms: separate loops in horizontal slices below the shoulders
arm_side = np.zeros(nv, int)   # +1 his left, -1 his right
for y0 in np.arange(-0.6, 0.02, 0.01):
    band = np.abs(y - y0) < 0.008
    eb = e_all[band[e_all[:, 0]] & band[e_all[:, 1]]]
    ids = np.nonzero(band)[0]
    if len(ids) == 0:
        continue
    loc = -np.ones(nv, int); loc[ids] = np.arange(len(ids))
    Ab = coo_matrix((np.ones(len(eb)), (loc[eb[:, 0]], loc[eb[:, 1]])), shape=(len(ids), len(ids)))
    n2, l2 = connected_components(Ab, directed=False)
    cnt = np.maximum(np.bincount(l2, minlength=n2), 1)
    cx = np.bincount(l2, weights=x[ids], minlength=n2) / cnt
    cz = np.bincount(l2, weights=z[ids], minlength=n2) / cnt
    left = (cx > 0.15) & (cz < 0.2)
    right = cx < -0.33
    arm_side[ids[left[l2]]] = 1
    arm_side[ids[right[l2]]] = -1
arm_side[spear] = 1
# shoulders blend in above the armpits
sh_l = np.clip((x - 0.1) / 0.12, 0, 1) * np.clip((0.24 - y) / 0.1, 0, 1) * (y >= 0.0)
sh_r = np.clip((-0.26 - x) / 0.12, 0, 1) * np.clip((0.24 - y) / 0.1, 0, 1) * (y >= 0.0)
arm_l = np.maximum((arm_side == 1).astype(float), sh_l) * (z > -0.2)
arm_r = np.maximum((arm_side == -1).astype(float), sh_r) * (z > -0.2)

Wt[:, BI['body']] = 1.0
head_t = np.clip((y - 0.25) / 0.07, 0, 1)
Wt[:, BI['head']] = head_t
Wt[:, BI['body']] -= head_t
for side, aw in (('l', arm_l), ('r', arm_r)):
    el = J['forearm_' + side]
    lo = np.clip((el[1] + 0.03 - y) / 0.07, 0, 1)
    if side == 'l':
        lo = np.maximum(lo, spear.astype(float))
    Wt[:, BI['forearm_' + side]] += aw * lo
    Wt[:, BI['arm_' + side]] += aw * (1 - lo)
    Wt[:, BI['body']] *= (1 - aw)
    Wt[:, BI['head']] *= (1 - aw)
# legs stay planted
root_t = np.clip((-0.42 - y) / 0.1, 0, 1) * (1 - spear) * (arm_side == 0)
Wt[:, BI['root']] += root_t
Wt[:, BI['body']] *= (1 - root_t)
Wt = np.clip(Wt, 0, None)
Wt /= Wt.sum(1, keepdims=True)
sp_lock = spear.copy()
for it in range(int(round(3 * DENS * DENS))):
    Wt = (np.asarray(Adj @ Wt) + Wt) / deg[:, None]
    Wt[sp_lock] = 0.0; Wt[sp_lock, BI['forearm_l']] = 1.0     # the spear stays rigid
order = np.argsort(-Wt, axis=1)[:, :4]
bw = np.take_along_axis(Wt, order, 1)
bw /= bw.sum(1, keepdims=True)

# ---------------------------------------------------------------- normals: soften, strongly on the face
face_zone = np.clip((y - 0.3) / 0.05, 0, 1) * np.clip((0.66 - y) / 0.05, 0, 1) * np.clip((z - 0.1) / 0.1, 0, 1)
Ns = N.copy()
for it in range(int(round(10 * DENS * DENS))):
    Ns = (np.asarray(Adj @ Ns) + Ns) / deg[:, None]
    Ns /= np.linalg.norm(Ns, axis=1, keepdims=True) + 1e-9
k_s = 0.3 + 0.6 * face_zone
N = N * (1 - k_s[:, None]) + Ns * k_s[:, None]
N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9

# ---------------------------------------------------------------- game space
SCALE = 0.86
def to_game(v):
    v = np.asarray(v, dtype=np.float64)
    out = np.empty_like(v)
    out[..., 0] = -v[..., 0] * SCALE
    out[..., 1] = (v[..., 1] + 1.0) * SCALE
    out[..., 2] = -v[..., 2] * SCALE
    return out
Pg = to_game(P)
Ng = N.copy(); Ng[:, 0] *= -1; Ng[:, 2] *= -1
rig = {'scale': SCALE, 'bones': [{'name': b, 'parent': PARENT[b], 'joint': to_game(J[b]).tolist()} for b in BONES]}
# where the spear touches the ground, for dust
rig['spear_butt'] = to_game(lo_c + lo_d * ((-0.98 - lo_c[1]) / lo_d[1])).tolist()
json.dump(rig, open(OUT + '/sculpt_rig.json', 'w'), indent=1)
col = np.concatenate([back, wf[:, None]], 1).astype(np.float32)
Pg.astype('<f4').tofile(OUT + '/sculpt_pos.bin'); Ng.astype('<f4').tofile(OUT + '/sculpt_nrm.bin')
uv.astype('<f4').tofile(OUT + '/sculpt_uv.bin'); col.tofile(OUT + '/sculpt_col.bin')
order.astype('<i4').tofile(OUT + '/sculpt_bones.bin'); bw.astype('<f4').tofile(OUT + '/sculpt_weights.bin')
I.astype('<i4').tofile(OUT + '/sculpt_idx.bin')
pal = np.array([[.3, .3, .3], [.8, .8, .8], [1, 1, 0], [0, 0, 1], [0, .7, 1], [1, 0, 0], [1, .6, 0]])
(Wt @ pal).astype('<f4').tofile(OUT + '/sculpt_dbg.bin')
print('verts', nv, 'tris', len(I), 'height %.2f m' % (Pg[:, 1].max() - Pg[:, 1].min()),
      'spear verts', int(spear.sum()), 'left arm', int((arm_l > 0.5).sum()), 'right arm', int((arm_r > 0.5).sum()))
