"""Texture, rig and convert the hero sculpt for the game.

Usage: build_hero.py <work dir> <out dir> [tag]
Inputs (glTF space: +Y up, character faces +Z, his right is -X):
  work/P_<tag>.npy, I_<tag>.npy, N_<tag>.npy   mesh from compact.py (Godot clockwise winding)
  work/img.npy                                  reference painting from segment.py
Outputs (game model space: faces -Z, his right is +X, feet at y=0):
  hero_*.bin arrays, hero_front.png, hero_rig.json

The sculpt stands with its arms hanging at its sides (a relaxed A-pose), so
every part is skinned, arms included.
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
TAG = sys.argv[3] if len(sys.argv) > 3 else 'full'
P = np.load(W + '/P_%s.npy' % TAG).astype(np.float64)
I = np.load(W + '/I_%s.npy' % TAG).astype(np.int64)
N = np.load(W + '/N_%s.npy' % TAG).astype(np.float64)
img = np.load(W + '/img.npy')
IH, IW, _ = img.shape
DENS = max(1.0, (len(I) / 32768) ** 0.5)   # ring-based steps were tuned on a 32k-triangle mesh
x, y, z = P[:, 0], P[:, 1], P[:, 2]

# ---------------------------------------------------------------- landmarks: mesh front (x, y) -> image (px, py)
LM = [
    ((-0.10, 0.47), (706, 200)), ((0.10, 0.47), (773, 201)),      # eyes
    ((-0.11, 0.53), (700, 174)), ((0.11, 0.53), (778, 174)),      # brows
    ((0.00, 0.41), (741, 232)), ((0.00, 0.33), (741, 256)),       # nose tip, mouth
    ((0.00, 0.27), (742, 282)),                                   # chin
    ((-0.19, 0.38), (674, 236)), ((0.19, 0.38), (802, 236)),      # cheeks
    ((0.00, 0.60), (738, 150)),                                   # hairline
    ((0.17, 0.99), (785, 28)),                                    # top spike
    ((-0.40, 0.57), (590, 168)), ((0.38, 0.52), (852, 142)),      # side spikes
    ((0.00, 0.12), (737, 340)),                                   # collar notch
    ((-0.32, 0.17), (603, 305)), ((0.33, 0.17), (818, 305)),      # shoulders
    ((-0.42, -0.31), (585, 470)), ((0.43, -0.31), (848, 465)),    # cuffs
    ((-0.42, -0.56), (585, 560)), ((0.44, -0.56), (845, 555)),    # finger tips
    ((0.00, -0.17), (728, 428)), ((0.10, -0.20), (763, 432)),     # belt, knot
    ((-0.28, -0.41), (622, 503)), ((0.30, -0.41), (808, 505)),    # hem corners
    ((0.00, -0.45), (720, 518)),                                  # crotch
    ((-0.20, -0.68), (658, 600)), ((0.20, -0.68), (777, 600)),    # knees
    ((-0.25, -0.97), (640, 710)), ((0.27, -0.97), (800, 700)),    # soles
    ((-0.38, -0.95), (605, 705)), ((0.42, -0.95), (845, 695)),    # toe corners
]
src = np.array([a for a, b in LM]); dst = np.array([b for a, b in LM], dtype=np.float64)
warp = RBFInterpolator(src, dst, kernel='thin_plate_spline', smoothing=0.5)
pix = warp(P[:, :2])

# ---------------------------------------------------------------- front texture: crop, pad edges, upscale
X0, Y0, X1, Y1 = 530, 0, 890, 740
TW, TH = 512, 1024
sat = img.max(2) - img.min(2)
core = ndi.binary_opening(sat > 0.09, iterations=1)
sil = Image.new('L', (IW, IH), 0); d = ImageDraw.Draw(sil)
front_tris = I[N[I].mean(1)[:, 2] > 0]
for t in front_tris:
    d.polygon([tuple(pix[t[0]]), tuple(pix[t[1]]), tuple(pix[t[2]])], fill=1)
sil = ndi.binary_erosion(np.asarray(sil).astype(bool), iterations=5)
valid = core | sil
bright = img.mean(2)
bgish = (sat < 0.07) & (bright > 0.56)
_lab, _ = ndi.label(bgish)              # only background that reaches the border (eye whites are light grey too)
_edge = np.unique(np.concatenate([_lab[0], _lab[-1], _lab[:, 0], _lab[:, -1]]))
bgish = np.isin(_lab, _edge[_edge > 0])
valid &= ~bgish
valid = ndi.binary_erosion(valid, iterations=3)
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
filled = img[idx[0], idx[1]]
crop = (np.clip(filled[Y0:Y1, X0:X1], 0, 1) * 255).astype(np.uint8)
Image.fromarray(crop).resize((TW, TH), Image.LANCZOS).save(OUT + '/hero_front.png')
uv = np.stack([(pix[:, 0] - X0) / (X1 - X0), (pix[:, 1] - Y0) / (Y1 - Y0)], 1)

# ---------------------------------------------------------------- arms: per-height cross sections
# Below the armpits each arm is its own loop in a horizontal slice; above, blend by distance from the body.
e_all = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
is_arm = np.zeros(len(P), bool)
for y0 in np.arange(-0.70, -0.04, 0.01):
    band = np.abs(y - y0) < 0.008
    eb = e_all[band[e_all[:, 0]] & band[e_all[:, 1]]]
    ids = np.nonzero(band)[0]
    if len(ids) == 0:
        continue
    loc = -np.ones(len(P), int); loc[ids] = np.arange(len(ids))
    A = coo_matrix((np.ones(len(eb)), (loc[eb[:, 0]], loc[eb[:, 1]])), shape=(len(ids), len(ids)))
    nc, lab = connected_components(A, directed=False)
    cx = np.bincount(lab, weights=x[ids], minlength=nc) / np.maximum(np.bincount(lab, minlength=nc), 1)
    arm_c = np.abs(cx) > 0.27
    is_arm[ids[arm_c[lab]]] = True
# shoulders and armpits: ramp outwards from the body
sh_ramp = np.clip((np.abs(x) - 0.22) / 0.1, 0, 1) * np.clip((0.2 - y) / 0.1, 0, 1) * (y >= -0.06)
arm_w = np.maximum(is_arm.astype(float), sh_ramp)

# ---------------------------------------------------------------- back colours, sampled from the reference
def sample(x0, y0, x1, y1):
    return np.median(img[y0:y1, x0:x1].reshape(-1, 3), axis=0)
HAIR = sample(700, 95, 740, 120) * 1.25
TUNIC = sample(690, 370, 725, 405)       # lit chest, between the collar and the belt
ROPE = sample(700, 424, 740, 432)
TROUS = sample(645, 560, 690, 620)
BOOTS = sample(615, 680, 660, 700)
SKIN = sample(688, 236, 706, 250)
print('palette hair', HAIR.round(2), 'tunic', TUNIC.round(2), 'rope', ROPE.round(2), 'trousers', TROUS.round(2),
      'boots', BOOTS.round(2), 'skin', SKIN.round(2))
back = np.tile(TUNIC, (len(P), 1))
back[y > 0.25] = HAIR
back[(y > 0.21) & (y <= 0.25) & (np.abs(x) < 0.09)] = SKIN       # nape
back[(y > 0.17) & (y <= 0.25) & ~((y > 0.21) & (np.abs(x) < 0.09))] = TUNIC
back[(y > -0.2) & (y < -0.14) & ~is_arm] = ROPE
back[(y < -0.41) & ~is_arm] = TROUS
back[(y < -0.86)] = BOOTS
back[is_arm & (y < -0.35)] = SKIN            # hands
rng = np.random.default_rng(3)
noise = (np.sin(x * 37) * np.sin(y * 29 + 1) * np.sin(z * 31 + 2)) * 0.05 + rng.normal(0, 0.015, len(P))
lum = back.mean(1, keepdims=True)
back = lum + (back - lum) * 0.7
back = np.clip(back * 1.5 * (1 + noise[:, None]), 0, 1)
# front weight from the normal: facing the camera -> painting, facing away -> painted back
wf = np.clip((N[:, 2] + 0.12) / 0.42, 0, 1)
wf = wf * wf * (3 - 2 * wf)
pxi = np.clip(pix.round().astype(int), 0, [IW - 1, IH - 1])
inside = ndi.binary_erosion(valid, iterations=2)[pxi[:, 1], pxi[:, 0]]
wf = np.where(inside, wf, 0.0)
# hidden faces: the inner side of arms and legs, which the painting can't see
inner = is_arm & (np.sign(N[:, 0]) == -np.sign(x)) & (np.abs(N[:, 0]) > 0.5)
wf[inner] = 0.0
print('verts on background', int((~inside).sum()))

# ---------------------------------------------------------------- skeleton (glTF space), then weights
J = {
    'body': np.array([0.0, -0.25, 0.0]),
    'head': np.array([0.0, 0.24, 0.02]),
    'arm_r': np.array([-0.30, 0.08, 0.0]), 'forearm_r': np.array([-0.355, -0.18, 0.0]), 'wrist_r': np.array([-0.395, -0.40, 0.0]),
    'arm_l': np.array([0.30, 0.08, 0.0]), 'forearm_l': np.array([0.355, -0.18, 0.0]), 'wrist_l': np.array([0.395, -0.40, 0.0]),
    'leg_r': np.array([-0.13, -0.42, 0.0]), 'shin_r': np.array([-0.16, -0.68, 0.02]), 'ankle_r': np.array([-0.18, -0.9, 0.0]),
    'leg_l': np.array([0.13, -0.42, 0.0]), 'shin_l': np.array([0.16, -0.68, 0.02]), 'ankle_l': np.array([0.18, -0.9, 0.0]),
}
BONES = ['body', 'head', 'arm_l', 'forearm_l', 'arm_r', 'forearm_r', 'leg_l', 'shin_l', 'leg_r', 'shin_r']
BI = {b: i for i, b in enumerate(BONES)}
nv = len(P)
Wt = np.zeros((nv, len(BONES)))
Wt[:, BI['body']] = 1.0
head_t = np.clip((y - 0.2) / 0.08, 0, 1)
Wt[:, BI['head']] = head_t
Wt[:, BI['body']] -= head_t
for side, sgn in (('l', 1), ('r', -1)):
    el = J['forearm_' + side]
    mine = arm_w * (np.sign(x) == sgn)
    lo_share = np.clip((el[1] + 0.04 - y) / 0.08, 0, 1)      # elbow blend
    Wt[:, BI['forearm_' + side]] += mine * lo_share
    Wt[:, BI['arm_' + side]] += mine * (1 - lo_share)
    Wt[:, BI['body']] *= (1 - mine)
    Wt[:, BI['head']] *= (1 - mine)
for side, sgn in (('l', 1), ('r', -1)):
    kn = J['shin_' + side]
    near_side = (np.sign(x) == sgn) & ~is_arm
    leg_t = np.clip((-0.38 - y) / 0.1, 0, 1) * near_side
    # the tunic hem (outer, in front of / behind the thigh) stays with the body
    hem = (y > -0.43) & (np.abs(z) > 0.12)
    leg_t = np.where(hem, leg_t * 0.3, leg_t)
    shin_share = np.clip((kn[1] + 0.05 - y) / 0.1, 0, 1)
    Wt[:, BI['shin_' + side]] += leg_t * shin_share
    Wt[:, BI['leg_' + side]] += leg_t * (1 - shin_share)
    Wt[:, BI['body']] *= (1 - leg_t)
Wt = np.clip(Wt, 0, None)
Wt /= Wt.sum(1, keepdims=True)
# smooth the weights a little across the surface so joints bend softly
_e1 = np.concatenate([e_all, e_all[:, ::-1]])
_Adj = coo_matrix((np.ones(len(_e1)), (_e1[:, 0], _e1[:, 1])), shape=(nv, nv)).tocsr()
_deg = np.asarray(_Adj.sum(1)).ravel() + 1
for it in range(int(round(3 * DENS * DENS))):
    Wt = (np.asarray(_Adj @ Wt) + Wt) / _deg[:, None]
order = np.argsort(-Wt, axis=1)[:, :4]
bw = np.take_along_axis(Wt, order, 1)
bw /= bw.sum(1, keepdims=True)

# ---------------------------------------------------------------- soften normals (strongly on the face, so the painted shading leads)
face_zone = np.clip((y - 0.22) / 0.06, 0, 1) * np.clip((z - 0.05) / 0.1, 0, 1) * (y < 0.62)
Ns = N.copy()
for it in range(int(round(12 * DENS * DENS))):
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

# Rest pose: arms hanging the way the game's own rig rests (down, slightly out, forearm a touch forward).
def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-8:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))
rig = {'bones': [], 'scale': SCALE}
target = {b: {'pos': Jg[b].copy(), 'basis': np.eye(3)} for b in BONES}
for side, sx in (('l', -1), ('r', 1)):   # game space: his left is -X
    sh, el, wr = Jg['arm_' + side], Jg['forearm_' + side], Jg['wrist_' + side]
    up_len = np.linalg.norm(el - sh); lo_len = np.linalg.norm(wr - el)
    hang_up = np.array([np.sin(0.09) * sx, -np.cos(0.09), 0.0])
    hang_lo = np.array([np.sin(0.09) * sx, -np.cos(0.12), -np.sin(0.12)]); hang_lo /= np.linalg.norm(hang_lo)
    target['arm_' + side] = {'pos': sh, 'basis': rot_between(el - sh, hang_up)}
    t_el = sh + hang_up * up_len
    target['forearm_' + side] = {'pos': t_el, 'basis': rot_between(wr - el, hang_lo)}
    rig['hand_' + side] = {'bind': (wr + (wr - el) * 0.3).tolist()}
parent = {'body': None, 'head': 'body', 'arm_l': 'body', 'forearm_l': 'arm_l', 'arm_r': 'body', 'forearm_r': 'arm_r',
          'leg_l': 'body', 'shin_l': 'leg_l', 'leg_r': 'body', 'shin_r': 'leg_r'}
for b in BONES:
    rig['bones'].append({'name': b, 'parent': parent[b], 'bind_pos': Jg[b].tolist(),
                         'target_pos': target[b]['pos'].tolist(), 'target_basis': target[b]['basis'].T.ravel().tolist()})
json.dump(rig, open(OUT + '/hero_rig.json', 'w'), indent=1)

col = np.concatenate([back, wf[:, None]], 1).astype(np.float32)
Pg.astype('<f4').tofile(OUT + '/hero_pos.bin'); Ng.astype('<f4').tofile(OUT + '/hero_nrm.bin')
uv.astype('<f4').tofile(OUT + '/hero_uv.bin'); col.tofile(OUT + '/hero_col.bin')
order.astype('<i4').tofile(OUT + '/hero_bones.bin'); bw.astype('<f4').tofile(OUT + '/hero_weights.bin')
I.astype('<i4').tofile(OUT + '/hero_idx.bin')
# debug colours: dominant bone
pal = np.array([[.8, .8, .8], [1, 1, 0], [0, 0, 1], [0, .6, 1], [1, 0, 0], [1, .5, 0], [0, 1, 0], [0, .5, 0], [1, 0, 1], [.5, 0, .5]])
(Wt @ pal).astype('<f4').tofile(OUT + '/hero_dbg.bin')
print('verts', nv, 'tris', len(I), 'height %.2f m' % (Pg[:, 1].max() - Pg[:, 1].min()))
print('arm verts', int(is_arm.sum()), 'front-facing share %.2f' % (wf > 0.5).mean())
