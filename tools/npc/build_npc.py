"""Texture and rig a villager sculpt (standing, arms at its sides) for the game.

Usage: build_npc.py <lady|child> <work dir> <out dir>
Inputs (glTF space: +Y up, faces +Z, their right is -X):
  work/P_full.npy, I_full.npy, N_full.npy   from tools/hero/compact.py
  work/img.npy                               the character art, from tools/hero/segment.py
Outputs (game space: faces -Z, feet at y=0): sculpt_*.bin, sculpt_front.png, sculpt_rig.json

Villagers don't walk, so legs ride a fixed root bone; body, head and both arms
can be posed for idles and gestures.
"""
import json, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw
from scipy.interpolate import RBFInterpolator
from scipy import ndimage as ndi
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

CONFIGS = {
    'lady': {
        'scale': 0.76,
        'crop': (590, 50, 840, 730),
        'landmarks': [
            ((0.00, 0.99), (716, 67)),                                  # bun
            ((-0.07, 0.77), (698, 145)), ((0.07, 0.77), (735, 145)),    # eyes
            ((0.00, 0.72), (716, 158)), ((0.00, 0.66), (716, 176)),     # nose, mouth
            ((0.00, 0.60), (716, 195)),                                 # chin
            ((-0.13, 0.73), (680, 154)), ((0.13, 0.73), (753, 154)),    # cheeks
            ((0.00, 0.47), (716, 249)),                                 # neckline
            ((-0.30, 0.50), (639, 235)), ((0.30, 0.50), (794, 235)),    # shoulders
            ((0.00, 0.12), (714, 354)),                                 # belt knot
            ((-0.35, -0.07), (616, 417)), ((0.35, -0.07), (824, 417)),  # cuffs
            ((-0.33, -0.33), (621, 485)), ((0.33, -0.33), (818, 485)),  # finger tips
            ((0.00, -0.52), (716, 558)),                                # apron hem
            ((-0.35, -0.70), (612, 622)), ((0.35, -0.70), (803, 622)),  # dress hem
            ((-0.20, -0.98), (653, 713)), ((0.20, -0.98), (780, 713)),  # boots
        ],
        'face_box': (670, 90, 765, 215),     # face pixels -> hair colour on the back of the head
        'hair_px': (705, 85, 728, 100),
        'front_only': 'apron',                # the apron isn't on her back
        'joints': {'root': (0, -1.0, 0), 'body': (0, -0.2, 0), 'head': (0, 0.55, 0),
                   'arm_r': (-0.26, 0.45, 0), 'forearm_r': (-0.33, 0.12, 0),
                   'arm_l': (0.26, 0.45, 0), 'forearm_l': (0.33, 0.12, 0)},
        'arm_x': 0.27, 'arm_top': 0.3, 'head_y': 0.53, 'root_y': -0.62,
    },
    'child': {
        'scale': 0.58,
        'crop': (590, 55, 840, 735),
        'landmarks': [
            ((0.00, 1.00), (716, 76)),                                  # hair top
            ((-0.075, 0.74), (695, 154)), ((0.075, 0.74), (736, 154)),  # eyes
            ((0.00, 0.68), (716, 167)), ((0.00, 0.60), (716, 185)),     # nose, mouth
            ((0.00, 0.53), (716, 208)),                                 # chin
            ((-0.16, 0.70), (675, 163)), ((0.16, 0.70), (757, 163)),    # cheeks
            ((0.00, 0.40), (716, 281)),                                 # collar slit
            ((-0.32, 0.45), (630, 281)), ((0.32, 0.45), (803, 281)),    # shoulders
            ((-0.37, 0.17), (616, 340)), ((0.37, 0.17), (812, 340)),    # sleeve ends
            ((0.00, 0.12), (716, 363)),                                 # belt knot
            ((-0.37, -0.30), (612, 499)), ((0.37, -0.30), (815, 499)),  # finger tips
            ((-0.30, -0.23), (635, 467)), ((0.30, -0.23), (798, 467)),  # tunic hem
            ((0.00, -0.27), (716, 495)),                                # crotch
            ((-0.17, -0.55), (675, 576)), ((0.17, -0.55), (757, 576)),  # knees
            ((-0.20, -0.98), (657, 717)), ((0.20, -0.98), (771, 717)),  # boots
        ],
        'face_box': (668, 118, 765, 225),
        'hair_px': (700, 85, 735, 105),
        'front_only': None,
        'joints': {'root': (0, -1.0, 0), 'body': (0, -0.25, 0), 'head': (0, 0.5, 0),
                   'arm_r': (-0.27, 0.4, 0), 'forearm_r': (-0.35, 0.1, 0),
                   'arm_l': (0.27, 0.4, 0), 'forearm_l': (0.35, 0.1, 0)},
        'arm_x': 0.29, 'arm_top': 0.28, 'head_y': 0.48, 'root_y': -0.3, 'unzip_extra': 0.0,
    },
}

NAME, W, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
C = CONFIGS[NAME]
P = np.load(W + '/P_full.npy').astype(np.float64)
I = np.load(W + '/I_full.npy').astype(np.int64)
N = np.load(W + '/N_full.npy').astype(np.float64)
img = np.load(W + '/img.npy')
IH, IW, _ = img.shape
x, y, z = P[:, 0], P[:, 1], P[:, 2]
nv = len(P)
DENS = max(1.0, (len(I) / 32768) ** 0.5)
e_all = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
_e1 = np.concatenate([e_all, e_all[:, ::-1]])
Adj = coo_matrix((np.ones(len(_e1)), (_e1[:, 0], _e1[:, 1])), shape=(nv, nv)).tocsr()
deg = np.asarray(Adj.sum(1)).ravel() + 1

# ---------------------------------------------------------------- front projection
src = np.array([a for a, b in C['landmarks']]); dst = np.array([b for a, b in C['landmarks']], dtype=np.float64)
pix = RBFInterpolator(src, dst, kernel='thin_plate_spline', smoothing=0.5)(P[:, :2])
X0, Y0, X1, Y1 = C['crop']
sat = img.max(2) - img.min(2); bright = img.mean(2)
bgish = (sat < 0.06) & (bright > 0.45)
lab, _ = ndi.label(bgish)
edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
bg = np.isin(lab, edge[edge > 0])
valid = ndi.binary_erosion(~bg, iterations=2)
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
filled = img[idx[0], idx[1]]
Image.fromarray((np.clip(filled[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)).resize((512, 1024), Image.LANCZOS).save(OUT + '/sculpt_front.png')
uv = np.stack([(pix[:, 0] - X0) / (X1 - X0), (pix[:, 1] - Y0) / (Y1 - Y0)], 1)

# ---------------------------------------------------------------- painted back
hsv = np.array([colorsys.rgb_to_hsv(*c) for c in img.reshape(-1, 3)]).reshape(IH, IW, 3)
yy, xx = np.mgrid[0:IH, 0:IW]
fx0, fy0, fx1, fy1 = C['face_box']
hx0, hy0, hx1, hy1 = C['hair_px']
HAIR = np.median(img[hy0:hy1, hx0:hx1].reshape(-1, 3), axis=0)
skin = valid & (xx > fx0) & (xx < fx1) & (yy > fy0) & (yy < fy1) & (hsv[..., 1] > 0.12) & (hsv[..., 0] < 0.12)
cmap = filled.copy()
cmap[skin] = HAIR
if C['front_only'] == 'apron':
    # apron: pale, warm, low saturation pixels in the middle of her front; behind it she wears the dress
    apron = valid & (hsv[..., 2] > 0.45) & (hsv[..., 1] < 0.35) & (hsv[..., 0] > 0.05) & (hsv[..., 0] < 0.16) & \
        (xx > 640) & (xx < 790) & (yy > 350) & (yy < 580)
    dress = valid & (hsv[..., 0] > 0.2) & (hsv[..., 0] < 0.45) & (hsv[..., 1] > 0.15)
    DRESS = np.median(img[dress], axis=0)
    cmap[apron] = DRESS
cmap = ndi.median_filter(cmap, size=(7, 7, 1))
pxi = np.clip(pix.round().astype(int), 0, [IW - 1, IH - 1])
back = cmap[pxi[:, 1], pxi[:, 0]]
rng = np.random.default_rng(7)
noise = (np.sin(x * 37) * np.sin(y * 29 + 1) * np.sin(z * 31 + 2)) * 0.05 + rng.normal(0, 0.015, nv)
back = np.clip(back * 1.3 * (1 + noise[:, None]), 0, 1)
wf = np.clip((N[:, 2] + 0.12) / 0.42, 0, 1)
wf = wf * wf * (3 - 2 * wf)
inside = ndi.binary_erosion(valid, iterations=2)[pxi[:, 1], pxi[:, 0]]
wf = np.where(inside, wf, 0.0)

# ---------------------------------------------------------------- skeleton and weights
J = {k: np.array(v, dtype=np.float64) for k, v in C['joints'].items()}
BONES = ['root', 'body', 'head', 'arm_l', 'forearm_l', 'arm_r', 'forearm_r']
PARENT = {'root': None, 'body': 'root', 'head': 'body', 'arm_l': 'body', 'forearm_l': 'arm_l', 'arm_r': 'body', 'forearm_r': 'arm_r'}
BI = {b: i for i, b in enumerate(BONES)}
# arms: find them where they hang free in horizontal slices, then follow a fitted
# centre line through the stretches where a sleeve brushes the body
samples = {1: [], -1: []}
for y0 in np.arange(-0.6, C['arm_top'], 0.01):
    band = np.abs(y - y0) < 0.004
    eb = e_all[band[e_all[:, 0]] & band[e_all[:, 1]]]
    ids = np.nonzero(band)[0]
    if len(ids) == 0:
        continue
    loc = -np.ones(nv, int); loc[ids] = np.arange(len(ids))
    Ab = coo_matrix((np.ones(len(eb)), (loc[eb[:, 0]], loc[eb[:, 1]])), shape=(len(ids), len(ids)))
    n2, l2 = connected_components(Ab, directed=False)
    sizes = np.bincount(l2, minlength=n2)
    for c in range(n2):
        if sizes[c] < 12 or sizes[c] > 0.4 * len(ids):
            continue
        q = P[ids[l2 == c]]
        cx = q[:, 0].mean()
        if abs(cx) > C['arm_x']:
            rad = np.linalg.norm(q[:, [0, 2]] - q[:, [0, 2]].mean(0), axis=1).max()
            samples[int(np.sign(cx))].append((y0, cx, q[:, 2].mean(), rad))
arm_side = np.zeros(nv, int)
for sd in (1, -1):
    a = np.array(samples[sd])
    ylo, yhi = a[:, 0].min() - 0.06, C['arm_top'] + 0.04
    fx = np.polyfit(a[:, 0], a[:, 1], 2); fz = np.polyfit(a[:, 0], a[:, 2], 2)
    rr = np.polyfit(a[:, 0], a[:, 3], 1)
    yc = np.clip(y, a[:, 0].min(), a[:, 0].max())
    d = np.hypot(x - np.polyval(fx, yc), z - np.polyval(fz, yc))
    r = np.clip(np.polyval(rr, yc), 0.04, 0.14) + 0.025
    cxl = np.polyval(fx, yc)
    # body surface facing the arm (the dress or tunic side it brushes) stays with the body
    body_side = (sd * N[:, 0] > 0.3) & (sd * x < sd * cxl)
    inside_arm = (d < r) & (y > ylo) & (y < yhi) & (np.sign(x) == sd) & ~body_side
    arm_side[inside_arm] = sd
    print('arm', sd, 'samples', len(a), 'y %.2f..%.2f' % (a[:, 0].min(), a[:, 0].max()), 'verts', int(inside_arm.sum()))
top = C['arm_top']
sh_ramp = lambda s: np.clip((s * x - (C['arm_x'] - 0.12)) / 0.1, 0, 1) * np.clip((top + 0.18 - y) / 0.12, 0, 1) * (y >= top - 0.02)
arm_l = np.maximum((arm_side == 1).astype(float), sh_ramp(1))
arm_r = np.maximum((arm_side == -1).astype(float), sh_ramp(-1))
Wt = np.zeros((nv, len(BONES)))
Wt[:, BI['body']] = 1.0
head_t = np.clip((y - C['head_y']) / 0.06, 0, 1)
Wt[:, BI['head']] = head_t
Wt[:, BI['body']] -= head_t
for side, aw in (('l', arm_l), ('r', arm_r)):
    el = J['forearm_' + side]
    lo = np.clip((el[1] + 0.03 - y) / 0.07, 0, 1)
    Wt[:, BI['forearm_' + side]] += aw * lo
    Wt[:, BI['arm_' + side]] += aw * (1 - lo)
    Wt[:, BI['body']] *= (1 - aw)
    Wt[:, BI['head']] *= (1 - aw)
root_t = np.clip((C['root_y'] - y) / 0.12, 0, 1) * (arm_side == 0)
Wt[:, BI['root']] += root_t
Wt[:, BI['body']] *= (1 - root_t)
Wt = np.clip(Wt, 0, None)
Wt /= Wt.sum(1, keepdims=True)
# soften only the shoulders, neck and waist; where a sleeve touches the body the
# split stays sharp so a raised arm doesn't drag the dress with it
soft = (y > C['arm_top'] - 0.12) | (np.abs(y - C['root_y']) < 0.1) & (arm_side == 0)
W0 = Wt.copy()
for it in range(int(round(2 * DENS * DENS))):
    Wt = (np.asarray(Adj @ Wt) + Wt) / deg[:, None]
    Wt[~soft] = W0[~soft]
# below the shoulders, anything that isn't arm stays off the arm bones
not_arm = (arm_side == 0) & (y < C['arm_top'] - 0.12)
Wt[np.ix_(not_arm, [BI['arm_l'], BI['forearm_l'], BI['arm_r'], BI['forearm_r']])] = 0.0
Wt /= Wt.sum(1, keepdims=True)
# where a sleeve was fused to the body, unzip it: drop the triangles bridging arm and body
armw_v = Wt[:, [BI['arm_l'], BI['forearm_l'], BI['arm_r'], BI['forearm_r']]].sum(1)
tw = armw_v[I]
bridge = (tw.max(1) - tw.min(1) > 0.5) & (y[I].max(1) < C['arm_top'] + C.get('unzip_extra', -0.1))
print('unzipped triangles', int(bridge.sum()))
I = I[~bridge]
order = np.argsort(-Wt, axis=1)[:, :4]
bw = np.take_along_axis(Wt, order, 1)
bw /= bw.sum(1, keepdims=True)

# ---------------------------------------------------------------- normals
face_zone = np.clip((y - C['head_y'] - 0.04) / 0.05, 0, 1) * np.clip((z - 0.05) / 0.1, 0, 1)
Ns = N.copy()
for it in range(int(round(10 * DENS * DENS))):
    Ns = (np.asarray(Adj @ Ns) + Ns) / deg[:, None]
    Ns /= np.linalg.norm(Ns, axis=1, keepdims=True) + 1e-9
k_s = 0.3 + 0.6 * face_zone
N = N * (1 - k_s[:, None]) + Ns * k_s[:, None]
N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9

# ---------------------------------------------------------------- game space
S = C['scale']
def to_game(v):
    v = np.asarray(v, dtype=np.float64); o = np.empty_like(v)
    o[..., 0] = -v[..., 0] * S; o[..., 1] = (v[..., 1] + 1.0) * S; o[..., 2] = -v[..., 2] * S
    return o
Pg = to_game(P)
Ng = N.copy(); Ng[:, 0] *= -1; Ng[:, 2] *= -1
rig = {'scale': S, 'bones': [{'name': b, 'parent': PARENT[b], 'joint': to_game(J[b]).tolist()} for b in BONES]}
json.dump(rig, open(OUT + '/sculpt_rig.json', 'w'), indent=1)
col = np.concatenate([back, wf[:, None]], 1).astype(np.float32)
Pg.astype('<f4').tofile(OUT + '/sculpt_pos.bin'); Ng.astype('<f4').tofile(OUT + '/sculpt_nrm.bin')
uv.astype('<f4').tofile(OUT + '/sculpt_uv.bin'); col.tofile(OUT + '/sculpt_col.bin')
order.astype('<i4').tofile(OUT + '/sculpt_bones.bin'); bw.astype('<f4').tofile(OUT + '/sculpt_weights.bin')
I.astype('<i4').tofile(OUT + '/sculpt_idx.bin')
pal = np.array([[.3, .3, .3], [.8, .8, .8], [1, 1, 0], [0, 0, 1], [0, .7, 1], [1, 0, 0], [1, .6, 0]])
(Wt @ pal).astype('<f4').tofile(OUT + '/sculpt_dbg.bin')
print(NAME, 'verts', nv, 'tris', len(I), 'height %.2f m' % (Pg[:, 1].max() - Pg[:, 1].min()),
      'arm verts l/r', int((arm_l > 0.5).sum()), int((arm_r > 0.5).sum()), 'hair', HAIR.round(2))
