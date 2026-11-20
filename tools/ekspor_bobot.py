"""Ambil bobot CDAE dari file .keras (zip berisi model.weights.h5) lalu simpan
sebagai float32 berurutan (kernel lalu bias, 7 lapis) ke assets/model/<jenis>.bin.
Dipakai oleh lib/cdae.dart. Jalankan: python tools/ekspor_bobot.py"""
import glob, io, os, zipfile
import h5py, numpy as np

LAPIS = ["conv1d"] + [f"conv1d_{i}" for i in range(1, 7)]
for path in sorted(glob.glob("model/*_cdae_seed42_best.keras")):
    jenis = os.path.basename(path).split("_")[0]
    if jenis == "mtb":          # model multitask diekspor oleh tools/mtb_numpy.py (urutan bobot lain)
        continue
    f = h5py.File(io.BytesIO(zipfile.ZipFile(path).read("model.weights.h5")), "r")
    bagian = []
    for l in LAPIS:
        k = np.asarray(f[f"layers/{l}/vars/0"], np.float32)  # (kernel, masuk, keluar)
        b = np.asarray(f[f"layers/{l}/vars/1"], np.float32)
        bagian += [k.ravel(), b.ravel()]
    out = np.concatenate(bagian).astype("<f4")
    out.tofile(f"assets/model/{jenis}.bin")
    print(jenis, out.size, "bobot")
