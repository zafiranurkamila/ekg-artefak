"""Buat CSV contoh dari data publik PhysioNet (hanya potongan yang dibutuhkan).

- EKG bersih: St Petersburg INCART 12-lead (257 Hz), lead II.
- Noise: MIT-BIH Noise Stress Test Database (em, ma, bw; 360 Hz -> 257 Hz).
Noise ditempel di dua jendela yang diketahui, dengan SNR 0 dB di jendela itu
(level uji berat di dataset Zaskia). Posisi noise yang sebenarnya
ditulis ke <nama>_kunci.txt untuk dibandingkan dengan hasil aplikasi.

Jalankan: python tools/buat_csv_physionet.py
"""
import os
import numpy as np
import wfdb
from scipy.signal import resample_poly

FS = 257
DURASI = 20.0
REKAMAN = "I01"
KELUAR = "contoh_csv"
JENDELA_NOISE = [(3.0, 6.0), (12.5, 15.0)]  # detik
SNR_DB = 0.0  # noise sekuat sinyal, mirip contoh dari Bapak
os.makedirs(KELUAR, exist_ok=True)

# cari 20 detik yang memuat PVC (anotasi 'V') supaya deteksi PVC ikut teruji
ann = wfdb.rdann(REKAMAN, "atr", pn_dir="incartdb")
v = [s for s, sym in zip(ann.sample, ann.symbol) if sym == "V"]
mulai = max(0, int(v[0] - 12 * FS)) if v else 0
n = int(DURASI * FS)
rec = wfdb.rdrecord(REKAMAN, pn_dir="incartdb", sampfrom=mulai, sampto=mulai + n, channel_names=["II"])
ekg = rec.p_signal[:, 0].astype(float)
ekg -= np.median(ekg)
pvc_dalam = [round((s - mulai) / FS, 2) for s in v if mulai <= s < mulai + n]
print(f"INCART {REKAMAN}: mulai sampel {mulai}, PVC di detik {pvc_dalam}")

np.savetxt(f"{KELUAR}/incart_{REKAMAN}_bersih.csv", ekg, fmt="%.5f")

for jenis in ("em", "ma", "bw"):
    nr = wfdb.rdrecord(jenis, pn_dir="nstdb", sampfrom=60 * 360, sampto=60 * 360 + int(30 * 360), channels=[0])
    noise = resample_poly(nr.p_signal[:, 0], FS, 360)
    noise -= noise.mean()
    x = ekg.copy()
    pos = 0
    kunci = []
    for a, z in JENDELA_NOISE:
        ia, iz = int(a * FS), int(z * FS)
        potong = noise[pos:pos + (iz - ia)]
        pos += iz - ia
        p_s = np.mean(ekg[ia:iz] ** 2)
        p_n = np.mean(potong ** 2)
        x[ia:iz] += potong * np.sqrt(p_s / (p_n * 10 ** (SNR_DB / 10)))
        kunci.append(f"{a:.2f} - {z:.2f} s")
    nama = f"incart_{REKAMAN}_{jenis}"
    np.savetxt(f"{KELUAR}/{nama}.csv", x, fmt="%.5f")
    with open(f"{KELUAR}/{nama}_kunci.txt", "w") as f:
        f.write(f"fs = {FS} Hz, durasi {DURASI:.0f} detik, lead II, noise {jenis.upper()} SNR {SNR_DB:.0f} dB\n")
        f.write("posisi noise sebenarnya:\n" + "\n".join(kunci) + "\n")
        f.write(f"PVC menurut anotasi INCART (detik): {pvc_dalam}\n")
    print("ditulis", nama)
