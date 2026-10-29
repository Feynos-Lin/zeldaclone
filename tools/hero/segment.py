import sys, numpy as np
from PIL import Image
from scipy import ndimage as ndi
src, out = sys.argv[1], sys.argv[2]
im = np.asarray(Image.open(src).convert('RGB')).astype(np.float32) / 255.0
H, W, _ = im.shape
# Background model: smooth gradient estimated from the image borders, fitted per pixel with a low-order polynomial.
yy, xx = np.mgrid[0:H, 0:W]
border = np.zeros((H, W), bool); b = 40
border[:b] = border[-b:] = True; border[:, :b] = border[:, -b:] = True
A = np.stack([np.ones(H * W), xx.ravel() / W, yy.ravel() / H, (xx.ravel() / W) ** 2, (yy.ravel() / H) ** 2, xx.ravel() * yy.ravel() / (W * H)], 1)
bg = np.zeros_like(im)
for c in range(3):
    coef, *_ = np.linalg.lstsq(A[border.ravel()], im[..., c].ravel()[border.ravel()], rcond=None)
    bg[..., c] = (A @ coef).reshape(H, W)
diff = np.linalg.norm(im - bg, axis=2)
sat = im.max(2) - im.min(2)
mask = (diff > 0.09) | (sat > 0.12)
mask = ndi.binary_opening(mask, iterations=2)
lab, n = ndi.label(mask)
sizes = ndi.sum(mask, lab, range(1, n + 1))
mask = lab == (1 + int(np.argmax(sizes)))
mask = ndi.binary_fill_holes(mask)
ys, xs = np.nonzero(mask)
print('bbox x', xs.min(), xs.max(), 'y', ys.min(), ys.max(), 'size', W, H)
np.save(out + '/img_mask.npy', mask); np.save(out + '/img.npy', im)
vis = (im * 255).astype(np.uint8).copy(); vis[~mask] = (vis[~mask] * 0.25).astype(np.uint8)
Image.fromarray(vis).save(out + '/img_mask_vis.png')
