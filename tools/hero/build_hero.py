"""Texture, rig and convert the hero model for the game.

Inputs (glTF space: +Y up, character faces +Z, his right is -X):
  P_hi/I_hi/N_hi.npy  simplified mesh, img.npy reference image
Outputs (game model space: faces -Z, his right is +X, feet at y=0):
  hero_*.bin arrays, hero_front.png, hero_rig.json
"""
import json, sys
import numpy as np
from PIL import Image
from scipy.interpolate import RBFInterpolator
from scipy import ndimage as ndi

W = sys.argv[1]
OUT = sys.argv[2]
P = np.load(W + '/P_hi.npy').astype(np.float64)
I = np.load(W + '/I_hi.npy')
N = np.load(W + '/N_hi.npy').astype(np.float64)
img = np.load(W + '/img.npy')
IH, IW, _ = img.shape

# ---------------------------------------------------------------- landmarks: mesh front (x, y) -> image (px, py)
LM = [
    ((-0.10, 0.50), (714, 203)), ((0.10, 0.50), (792, 202)),      # eyes
    ((-0.11, 0.56), (717, 172)), ((0.11, 0.56), (795, 172)),      # brows
    ((0.00, 0.42), (748, 230)), ((0.00, 0.33), (751, 258)),       # nose tip, mouth
    ((0.00, 0.24), (752, 286)),                                   # chin
    ((-0.20, 0.40), (676, 232)), ((0.20, 0.40), (828, 232)),      # cheeks
    ((0.00, 0.62), (745, 150)),                                   # hairline
    ((0.13, 0.99), (773, 18)), ((-0.27, 0.90), (643, 55)),        # hair tips
    ((-0.40, 0.57), (592, 158)), ((0.39, 0.46), (842, 212)),
    ((0.35, 0.75), (858, 135)), ((-0.32, 0.43), (625, 245)),
    ((0.00, 0.20), (745, 300)),                                   # collar
    ((-0.36, 0.20), (600, 295)), ((0.38, 0.20), (838, 300)),      # shoulders
    ((-0.38, -0.09), (592, 395)), ((0.43, -0.07), (845, 400)),    # elbows
    ((-0.18, 0.02), (700, 345)), ((0.14, 0.01), (790, 385)),      # fists
    ((0.00, -0.19), (722, 432)), ((0.05, -0.30), (760, 470)),     # belt, knot
    ((-0.28, -0.405), (620, 500)), ((0.28, -0.405), (808, 500)),  # hem corners
    ((0.00, -0.43), (725, 510)),                                  # crotch
    ((-0.22, -0.655), (660, 590)), ((0.20, -0.655), (775, 590)),  # knees
    ((-0.22, -0.95), (640, 692)), ((0.21, -0.95), (800, 692)),    # feet
    ((-0.35, -0.98), (600, 712)), ((0.37, -0.98), (840, 712)),    # sole corners
]
src = np.array([a for a, b in LM]); dst = np.array([b for a, b in LM], dtype=np.float64)
warp = RBFInterpolator(src, dst, kernel='thin_plate_spline', smoothing=0.5)
pix = warp(P[:, :2])

# ---------------------------------------------------------------- front texture: crop, pad edges, upscale
X0, Y0, X1, Y1 = 540, 0, 900, 740
TW, TH = 512, 1024
sat = img.max(2) - img.min(2)
core = ndi.binary_opening(sat > 0.09, iterations=1)
# Pixels the warped mesh outline covers count as character too (the grey trousers aren't saturated).
from PIL import ImageDraw
sil = Image.new('L', (IW, IH), 0); d = ImageDraw.Draw(sil)
for t in I:
    d.polygon([tuple(pix[t[0]]), tuple(pix[t[1]]), tuple(pix[t[2]])], fill=1)
sil = ndi.binary_erosion(np.asarray(sil).astype(bool), iterations=5)
valid = core | sil
# Keep only pixels clearly unlike the background inside the outline: background is light, grey and flat.
bright = img.mean(2)
bgish = (sat < 0.07) & (bright > 0.56)
# only background that reaches the image border (eye whites are light and grey too)
_lab, _ = ndi.label(bgish)
_edge = np.unique(np.concatenate([_lab[0], _lab[-1], _lab[:, 0], _lab[:, -1]]))
bgish = np.isin(_lab, _edge[_edge > 0])
valid &= ~bgish
valid = ndi.binary_erosion(valid, iterations=3)
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
filled = img[idx[0], idx[1]]
crop = (np.clip(filled[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)
front = Image.fromarray(crop).resize((TW, TH), Image.LANCZOS)
front.save(OUT + '/hero_front.png')
uv = np.stack([(pix[:, 0] - X0) / (X1 - X0), (pix[:, 1] - Y0) / (Y1 - Y0)], 1)

# ---------------------------------------------------------------- back colours, sampled from the reference
def sample(x0, y0, x1, y1):
    reg = img[y0:y1, x0:x1].reshape(-1, 3)
    return np.median(reg, axis=0)
HAIR = sample(690, 70, 730, 110) * 1.25
TUNIC = sample(630, 440, 680, 490) * 1.35
ROPE = sample(700, 426, 740, 438)
TROUS = sample(640, 540, 690, 600)
BOOTS = sample(620, 670, 660, 700)
SKIN = sample(730, 240, 770, 260)
print('palette hair', HAIR.round(2), 'tunic', TUNIC.round(2), 'rope', ROPE.round(2), 'trousers', TROUS.round(2), 'boots', BOOTS.round(2), 'skin', SKIN.round(2))

x, y, z = P[:, 0], P[:, 1], P[:, 2]
FIST = [np.array([-0.18, 0.02, 0.27]), np.array([0.14, 0.01, 0.27])]
back = np.tile(TUNIC, (len(P), 1))
back[y > 0.2] = HAIR
belt = (y > -0.25) & (y < -0.14)
back[belt] = ROPE
back[(y < -0.42)] = TROUS
back[(y < -0.85)] = BOOTS
for f in FIST:
    back[np.linalg.norm(P - f, axis=1) < 0.11] = SKIN
# a little painted variation so the back isn't flat
rng = np.random.default_rng(3)
noise = (np.sin(x * 37) * np.sin(y * 29 + 1) * np.sin(z * 31 + 2)) * 0.05 + rng.normal(0, 0.015, len(P))
lum = back.mean(1, keepdims=True)
back = lum + (back - lum) * 0.6
back[(y < -0.42) & (y >= -0.85)] = TROUS.mean() * 0.95 + (TROUS - TROUS.mean()) * 0.25
back = np.clip(back * 1.4 * (1 + noise[:, None]), 0, 1)
# front weight from the bind-pose normal: facing the camera -> image, facing away -> painted back
wf = np.clip((N[:, 2] + 0.12) / 0.42, 0, 1)
wf = wf * wf * (3 - 2 * wf)
# vertices whose image pixel is background (outline mismatch) use the painted colour instead
pxi = np.clip(pix.round().astype(int), 0, [IW - 1, IH - 1])
inside = ndi.binary_erosion(valid, iterations=2)[pxi[:, 1], pxi[:, 0]]
wf = np.where(inside, wf, np.minimum(wf, 0.0))
print('verts on background', (~inside).sum())

# ---------------------------------------------------------------- skeleton (glTF space), then weights
J = {
    'body': np.array([0.0, -0.2, 0.0]),
    'head': np.array([0.0, 0.2, 0.02]),
    # his right side is -X in glTF space
    'arm_r': np.array([-0.27, 0.15, 0.0]), 'forearm_r': np.array([-0.33, -0.07, 0.03]), 'wrist_r': np.array([-0.21, 0.0, 0.22]),
    'arm_l': np.array([0.27, 0.15, 0.0]), 'forearm_l': np.array([0.34, -0.06, 0.03]), 'wrist_l': np.array([0.17, 0.0, 0.22]),
    'leg_r': np.array([-0.13, -0.38, 0.0]), 'shin_r': np.array([-0.21, -0.66, 0.02]), 'ankle_r': np.array([-0.22, -0.9, 0.0]),
    'leg_l': np.array([0.13, -0.38, 0.0]), 'shin_l': np.array([0.2, -0.66, 0.02]), 'ankle_l': np.array([0.21, -0.9, 0.0]),
}
BONES = ['body', 'head', 'arm_l', 'forearm_l', 'arm_r', 'forearm_r', 'leg_l', 'shin_l', 'leg_r', 'shin_r']
BI = {b: i for i, b in enumerate(BONES)}

def seg_dist(p, a, b):
    ab = b - a; t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1), t

nv = len(P)
Wt = np.zeros((nv, len(BONES)))
# torso and head
Wt[:, BI['body']] = 1.0
head_t = np.clip((y - 0.17) / 0.08, 0, 1)
Wt[:, BI['head']] = head_t
Wt[:, BI['body']] -= head_t
# arms: vertices outside the torso core (to the sides, or in front of the chest)
for side, sgn in (('l', 1), ('r', -1)):
    sh, el, wr = J['arm_' + side], J['forearm_' + side], J['wrist_' + side]
    d_up, _ = seg_dist(P, sh, el)
    d_lo, t_lo = seg_dist(P, el, wr + (wr - el) * 0.35)
    near_side = (np.sign(x) == sgn) | (np.abs(x) < 0.03)
    in_band = (y > -0.25) & (y < 0.26)
    outside = (np.abs(x) > 0.24) | (z > 0.17)
    arm = near_side & in_band & outside & (np.minimum(d_up, d_lo) < 0.16)
    # blend upper arm <-> forearm around the elbow, upper arm <-> body at the shoulder
    lo_share = np.clip((d_up - d_lo) / 0.06 + 0.5, 0, 1)
    sh_blend = np.clip((np.linalg.norm(P - sh, axis=1) - 0.04) / 0.08, 0, 1)
    arm_w = np.where(arm, sh_blend, 0.0)
    Wt[:, BI['forearm_' + side]] += arm_w * lo_share
    Wt[:, BI['arm_' + side]] += arm_w * (1 - lo_share)
    Wt[:, BI['body']] *= (1 - arm_w)
    Wt[:, BI['head']] *= (1 - arm_w)
# legs: below the hips, split by side; blend thigh <-> shin at the knee, thigh <-> body at the hip
for side, sgn in (('l', 1), ('r', -1)):
    hp, kn, an = J['leg_' + side], J['shin_' + side], J['ankle_' + side]
    near_side = np.sign(x) == sgn
    leg_t = np.clip((-0.33 - y) / 0.12, 0, 1) * near_side
    shin_share = np.clip((kn[1] + 0.05 - y) / 0.1, 0, 1)
    Wt[:, BI['shin_' + side]] += leg_t * shin_share
    Wt[:, BI['leg_' + side]] += leg_t * (1 - shin_share)
    Wt[:, BI['body']] *= (1 - leg_t)
# the tunic hem stays with the body
Wt = np.clip(Wt, 0, None)
Wt /= Wt.sum(1, keepdims=True)

# ---------------------------------------------------------------- cut the arms off
# The sculpt's hands are fused to each other and to the chest, so the arms can't be re-posed
# without tearing. The game keeps its own animated arms; the sculpt keeps head, torso and legs.
ARMB = [BI[b] for b in ('arm_l', 'forearm_l', 'arm_r', 'forearm_r')]
arm_sum = Wt[:, ARMB].sum(1)
gone = arm_sum > 0.3
# the torso front sits at z ~0.10-0.14; anything well in front of it in the arm band is forearm/hand
_band = (y > -0.25) & (y < 0.17)
gone |= _band & ((z > 0.165) | (np.abs(x) > 0.25))
# eat the sleeve flaps left around the cut: grow into the shoulder/side zone a few rings
_e0 = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
_zone = _band & ((np.abs(x) > 0.19) | (z > 0.14)) | (arm_sum > 0.12)
for _ in range(4):
    _g = gone.copy()
    _g[_e0[:, 1][gone[_e0[:, 0]]]] = True
    _g[_e0[:, 0][gone[_e0[:, 1]]]] = True
    gone = gone | (_g & _zone)
# drop anything the cut leaves floating
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
_k = I[~gone[I].any(1)]
_e = np.concatenate([_k[:, [0, 1]], _k[:, [1, 2]]])
_A = coo_matrix((np.ones(len(_e)), (_e[:, 0], _e[:, 1])), shape=(len(P), len(P)))
_n, _lab = connected_components(_A, directed=False)
_sizes = np.bincount(_lab[_k[:, 0]], minlength=_n)
gone |= _lab != np.argmax(_sizes)
tri_gone = gone[I].any(1)
gone_tris_pix = pix[I[tri_gone]]
keep_tris = I[~tri_gone]
used = np.zeros(len(P), bool); used[keep_tris.ravel()] = True
remap = -np.ones(len(P), int); remap[used] = np.arange(used.sum())
P, N, uv, back, wf, pix, Wt = P[used], N[used], uv[used], back[used], wf[used], pix[used], Wt[used]
I = remap[keep_tris]
# close the openings with fans around each boundary loop
from collections import defaultdict
ecount = defaultdict(int)
for t in I:
    for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
        ecount[(a, b)] += 1
bnd = {}
for (a, b), c in ecount.items():
    if (b, a) not in ecount:
        bnd[b] = a   # walk the boundary reversed so the fill faces outwards like its neighbours
loops = []
seen = set()
for st in list(bnd.keys()):
    if st in seen:
        continue
    loop = [st]; seen.add(st); cur = bnd[st]
    while cur != st and cur in bnd and cur not in seen:
        loop.append(cur); seen.add(cur); cur = bnd[cur]
    if len(loop) >= 3:
        loops.append(loop)
newP, newN, newT = [], [], []
nv0 = len(P)
for lp in loops:
    c = P[lp].mean(0)
    nrm = N[lp].mean(0)
    if np.linalg.norm(nrm) > 1e-6:
        nrm = nrm / np.linalg.norm(nrm)
    ci = nv0 + len(newP)
    newP.append(c); newN.append(nrm)
    for k in range(len(lp)):
        newT.append([lp[k], lp[(k + 1) % len(lp)], ci])
print('arm cut: removed verts', int(gone.sum()), 'loops', len(loops), [len(l) for l in loops])
if newP:
    k = len(newP)
    near = [l[0] for l in loops]
    P = np.concatenate([P, np.array(newP)]); N = np.concatenate([N, np.array(newN)])
    uv = np.concatenate([uv, uv[near]]); back = np.concatenate([back, back[near]])
    wf = np.concatenate([wf, np.zeros(k)]); pix = np.concatenate([pix, pix[near]])
    Wt = np.concatenate([Wt, Wt[near]])
    I = np.concatenate([I, np.array(newT)])
# fill-loop rims take the painted colour too
for lp in loops:
    wf[lp] = np.minimum(wf[lp], 0.3)
Wt[:, ARMB] = 0.0
Wt /= np.maximum(Wt.sum(1, keepdims=True), 1e-9)
order = np.argsort(-Wt, axis=1)[:, :4]
bw = np.take_along_axis(Wt, order, 1)
bw /= bw.sum(1, keepdims=True)

# ---------------------------------------------------------------- soften normals
from scipy.sparse import coo_matrix as _coo
_e1 = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]], I[:, [1, 0]], I[:, [2, 1]], I[:, [0, 2]]])
_Adj = _coo((np.ones(len(_e1)), (_e1[:, 0], _e1[:, 1])), shape=(len(P), len(P))).tocsr()
_deg = np.asarray(_Adj.sum(1)).ravel() + 1
face_zone = np.clip((P[:, 1] - 0.18) / 0.06, 0, 1) * np.clip((P[:, 2] - 0.05) / 0.1, 0, 1) * (P[:, 1] < 0.62)
Ns = N.copy()
for it in range(12):
    Ns = (np.asarray(_Adj @ Ns) + Ns) / _deg[:, None]
    Ns /= np.linalg.norm(Ns, axis=1, keepdims=True) + 1e-9
k_s = 0.35 + 0.65 * face_zone
N = N * (1 - k_s[:, None]) + Ns * k_s[:, None]
N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9

# ---------------------------------------------------------------- convert to game space
SCALE = 0.82
def to_game(v):
    v = np.asarray(v, dtype=np.float64)
    out = np.empty_like(v)
    out[..., 0] = -v[..., 0] * SCALE
    out[..., 1] = (v[..., 1] + 1.0) * SCALE
    out[..., 2] = -v[..., 2] * SCALE
    return out
Pg = to_game(P)
Ng = N.copy(); Ng[:, 0] *= -1; Ng[:, 2] *= -1
Jg = {k: to_game(v) for k, v in J.items()}

# Target rest pose: arms hanging the way the game's own skeleton rests (down, slightly out),
# forearms bent a touch forward; everything else stays as modelled.
def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-8:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))
rig = {'bones': [], 'scale': SCALE}
target = {}
for b in BONES:
    target[b] = {'pos': Jg[b].copy(), 'basis': np.eye(3)}
for side, sx in (('l', -1), ('r', 1)):   # game space: his left is -X
    sh, el = Jg['arm_' + side], Jg['forearm_' + side]
    wr = Jg['wrist_' + side]
    up_len = np.linalg.norm(el - sh); lo_len = np.linalg.norm(wr - el)
    hang_up = np.array([np.sin(0.09) * sx, -np.cos(0.09), 0.0])
    hang_lo = np.array([np.sin(0.09) * sx, -np.cos(0.12), -np.sin(0.12)]); hang_lo /= np.linalg.norm(hang_lo)
    R_up = rot_between(el - sh, hang_up)
    R_lo = rot_between(wr - el, hang_lo)
    target['arm_' + side] = {'pos': sh, 'basis': R_up}
    t_el = sh + hang_up * up_len
    target['forearm_' + side] = {'pos': t_el, 'basis': R_lo}
    rig['hand_' + side] = {'bind': (wr + (wr - el) * 0.25).tolist(), 'target': (t_el + hang_lo * lo_len * 1.25).tolist()}
parent = {'body': None, 'head': 'body', 'arm_l': 'body', 'forearm_l': 'arm_l', 'arm_r': 'body', 'forearm_r': 'arm_r',
          'leg_l': 'body', 'shin_l': 'leg_l', 'leg_r': 'body', 'shin_r': 'leg_r'}
for b in BONES:
    rig['bones'].append({'name': b, 'joint': b, 'parent': parent[b], 'bind_pos': Jg[b].tolist(),
                         'target_pos': target[b]['pos'].tolist(), 'target_basis': target[b]['basis'].T.ravel().tolist()})
json.dump(rig, open(OUT + '/hero_rig.json', 'w'), indent=1)

import cv2
amask = Image.new('L', (IW, IH), 0); d2 = ImageDraw.Draw(amask)
for t in gone_tris_pix:
    d2.polygon([tuple(q) for q in t], fill=255)
amask = ndi.binary_dilation(np.asarray(amask) > 0, iterations=9)
# keep the face, collar and belt untouched
img8 = (np.clip(filled, 0, 1) * 255).astype(np.uint8)
inp = cv2.inpaint(img8, amask.astype(np.uint8) * 255, 12, cv2.INPAINT_TELEA).astype(np.float64) / 255
# soften the smears and add a little cloth grain
blur = ndi.gaussian_filter(inp, (14, 14, 0))
grain = (rng.normal(0, 0.02, inp.shape[:2]) )[..., None]
inp = np.where(amask[..., None], blur * (1 + grain), inp)
Image.fromarray((np.clip(inp[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)).resize((TW, TH), Image.LANCZOS).save(OUT + '/hero_front.png')
Image.fromarray((amask[Y0:Y1, X0:X1] * 255).astype(np.uint8)).save(OUT + '/arm_mask.png')

col = np.concatenate([back, wf[:, None]], 1).astype(np.float32)
Pg.astype('<f4').tofile(OUT + '/hero_pos.bin'); Ng.astype('<f4').tofile(OUT + '/hero_nrm.bin')
uv.astype('<f4').tofile(OUT + '/hero_uv.bin'); col.tofile(OUT + '/hero_col.bin')
order.astype('<i4').tofile(OUT + '/hero_bones.bin'); bw.astype('<f4').tofile(OUT + '/hero_weights.bin')
I.astype('<i4').tofile(OUT + '/hero_idx.bin')
# weight debug colours per dominant bone
dbg = np.array([[0.8, 0.8, 0.8], [1, 0.9, 0.2], [0.2, 0.5, 1], [0.1, 0.9, 1], [1, 0.3, 0.3], [1, 0.6, 0.2], [0.3, 0.9, 0.3], [0.1, 0.5, 0.1], [0.8, 0.3, 0.9], [0.5, 0.1, 0.6]])
(dbg[order[:, 0]] * bw[:, :1] + 0.0).astype('<f4').tofile(OUT + '/hero_dbg.bin')
print('verts', len(Pg), 'tris', len(I), 'height %.2f m' % (Pg[:, 1].max() - Pg[:, 1].min()))
print('front-facing share %.2f' % (wf > 0.5).mean())
