"""Forward pass model multitask Zaskia (MTB-CDAE) dengan numpy, untuk memeriksa ekspor ke Dart.
Kelas: 0 = BW, 1 = MA, 2 = EM (urutan KINDS di TRAINING_MULTITASK_B_V4)."""
import io, zipfile
import h5py
import numpy as np

KELAS = ["BW", "MA", "EM"]


def muat(path="model/mtb_cdae_seed42_best.keras"):
    f = h5py.File(io.BytesIO(zipfile.ZipFile(path).read("model.weights.h5")), "r")
    g = lambda n, i: np.array(f[f"layers/{n}/vars/{i}"], dtype=np.float32)
    return {n: [g(n, i) for i in range(len(f[f"layers/{n}/vars"]))] for n in f["layers"]}


def conv(x, k, b, s=1, d=1, relu=True):
    n = x.shape[0]; ke = 4 * d + 1; out = (n + s - 1) // s
    pt = max((out - 1) * s + ke - n, 0); pl = pt // 2
    xp = np.zeros((n + pt, x.shape[1]), np.float32); xp[pl:pl + n] = x
    y = np.zeros((out, k.shape[2]), np.float32) + b
    for j in range(5):
        y += xp[j * d: j * d + (out - 1) * s + 1: s] @ k[j]
    return np.maximum(y, 0) if relu else y


def jalankan(w, sinyal):
    skala = np.percentile(np.abs(sinyal), 99.5) + 1e-8
    nl = w["conv1d"][0].shape[1]                      # 1 (model 1 lead) atau 12 (model lama)
    x = np.repeat((sinyal / skala)[:, None], nl, 1).astype(np.float32)
    x = conv(x, *w["conv1d"], s=2); x = conv(x, *w["conv1d_1"], s=2)
    x = conv(x, *w["conv1d_2"]); z = conv(x, *w["conv1d_3"], d=2)
    c = np.concatenate([z.mean(0), z.max(0)])
    ga, be, mu, va = w["batch_normalization"]
    c = (c - mu) / np.sqrt(va + 1e-3) * ga + be
    c = np.maximum(c @ w["dense"][0] + w["dense"][1], 0)
    lg = c @ w["dense_1"][0] + w["dense_1"][1]; p = np.exp(lg - lg.max()); p /= p.sum()
    y = np.concatenate([z, np.repeat(p[None], z.shape[0], 0)], 1)
    y = np.repeat(y, 2, 0); y = conv(y, *w["conv1d_4"])
    y = np.repeat(y, 2, 0); y = conv(y, *w["conv1d_5"])
    y = conv(y, *w["conv1d_6"], relu=False)
    return y.mean(1) * skala, p


def ekspor(w, keluar="assets/model/mtb.bin"):
    urut = []
    for n in ["conv1d", "conv1d_1", "conv1d_2", "conv1d_3"]: urut += w[n]
    urut += w["batch_normalization"] + w["dense"] + w["dense_1"]
    for n in ["conv1d_4", "conv1d_5", "conv1d_6"]: urut += w[n]
    v = np.concatenate([a.ravel() for a in urut]).astype("<f4"); v.tofile(keluar); return v.size


if __name__ == "__main__":
    w = muat(); print("bobot", ekspor(w))
