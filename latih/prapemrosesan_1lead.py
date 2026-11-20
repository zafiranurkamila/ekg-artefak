"""Prapemrosesan 1 lead (lead II), diadaptasi dari PRAPEMROSESAN_V4 (Zaskia).

Sama dengan versi Zaskia: INCART 257 Hz, filter band-pass 0,5-40 Hz (Butterworth orde 2,
filtfilt) + notch 50 Hz (Q 30) pada rekaman utuh, jendela 768 sampel, noise NSTDB
(bw, ma, em) di-resample 360 -> 257 Hz, potongan 514 sampel ditempel di posisi acak,
SNR acak 0-10 dB (latih/val) dan 5 dB (uji), skala = persentil 99,5 |sinyal kotor|,
split per pasien 70/15/15, potongan noise dibagi berurutan menurut waktu.

Beda: hanya lead II, noise 1 kanal NSTDB (tanpa 9 elektroda), dan aturan sebaran PVC
saat split diganti split acak per pasien (seed 42).

Jalankan:  python latih/prapemrosesan_1lead.py --incart ~/ekg/data/incartdb --nstdb ~/ekg/data/nstdb --keluar ~/ekg/data/processed_1lead
Hasil per jenis noise (bw, ma, em): X_{train,val,test}_noisy.npy, X_{..}_clean.npy, valid_{..}.npy, scale_{..}.npy
dengan bentuk (N, 768, 1).
"""
import argparse, glob, os, re
import numpy as np
import wfdb
from scipy.signal import butter, filtfilt, iirnotch, resample_poly

FS, W, LN, LEAD = 257, 768, 514, 1          # LEAD 1 = lead II
KINDS = ("bw", "ma", "em")
SPLITS = ("train", "val", "test")
BEAT = set("NLRejAaJSVEFP/fQ")


def baca_bersih(incart):
    b, a = butter(2, [0.5 / (FS / 2), 40 / (FS / 2)], btype="band")
    bn, an = iirnotch(50.0, 30.0, FS)
    segs, subjek = [], []
    files = sorted(glob.glob(os.path.join(incart, "*.hea")))
    assert files, f"tidak ada .hea di {incart}"
    for i, f in enumerate(files, 1):
        rec = f[:-4]
        x, hdr = wfdb.rdsamp(rec, channels=[LEAD])
        if hdr["fs"] != FS:
            continue
        ann = wfdb.rdann(rec, "atr")
        samp = np.asarray(ann.sample)[np.isin(ann.symbol, list(BEAT))]
        y = filtfilt(bn, an, filtfilt(b, a, x[:, 0]))
        m = re.search(r"patient\s*(\d+)", " ".join(hdr["comments"] or []), re.I)
        s = f"pasien_{int(m.group(1)):02d}" if m else os.path.basename(rec)
        for k in range(len(y) // W):
            a0 = k * W
            if not ((samp >= a0) & (samp < a0 + W)).any():
                continue
            seg = y[a0:a0 + W]
            if seg.std() < 1e-3:                      # lead datar
                continue
            segs.append(seg.astype(np.float32)); subjek.append(s)
        print(f"  [{i}/{len(files)}] {os.path.basename(rec)} {s}: total {len(segs):,} segmen")
    return np.stack(segs), np.array(subjek)


def split_pasien(subjek, seed=42):
    unik = np.array(sorted(set(subjek)))
    np.random.default_rng(seed).shuffle(unik)
    n = len(unik); a = int(round(0.70 * n)); b = a + int(round(0.15 * n))
    grup = {"train": set(unik[:a]), "val": set(unik[a:b]), "test": set(unik[b:])}
    return {s: np.where(np.isin(subjek, list(g)))[0] for s, g in grup.items()}


def pool_noise(nstdb, kind):
    x, hdr = wfdb.rdsamp(os.path.join(nstdb, kind))
    x = resample_poly(x, FS, hdr["fs"], axis=0); x = x - x.mean(0, keepdims=True)
    n = len(x) // LN
    seg = x[:n * LN].reshape(n, LN, x.shape[1])
    sd = seg.std(1); ok = sd > 1e-9
    seg = (seg - seg.mean(1, keepdims=True)) / np.where(ok, sd, 1.0)[:, None, :]
    n_tr, n_va = int(0.70 * n), int(round(0.15 * n))
    ids = {"train": np.arange(0, n_tr), "val": np.arange(n_tr + 1, n_tr + 1 + n_va),
           "test": np.arange(n_tr + 2 + n_va, n)}
    return seg, ok, ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--incart", required=True); ap.add_argument("--nstdb", required=True)
    ap.add_argument("--keluar", required=True)
    arg = ap.parse_args()
    X, subjek = baca_bersih(os.path.expanduser(arg.incart))
    idx = split_pasien(subjek)
    print({s: len(v) for s, v in idx.items()}, "segmen")
    pools = {k: pool_noise(os.path.expanduser(arg.nstdb), k) for k in KINDS}
    for kind in KINDS:
        seg, ok, ids = pools[kind]
        d = os.path.join(os.path.expanduser(arg.keluar), kind); os.makedirs(d, exist_ok=True)
        for sp in SPLITS:
            rows = idx[sp]; N = len(rows)
            Xn = np.empty((N, W, 1), np.float32); Xc = np.empty((N, W, 1), np.float32); sc = np.empty(N, np.float32)
            for j, r in enumerate(rows):
                bersama = np.random.default_rng([42, SPLITS.index(sp), int(r)])     # posisi & SNR sama untuk ketiga jenis
                acak = np.random.default_rng([42, KINDS.index(kind), SPLITS.index(sp), int(r)])
                o = int(bersama.integers(0, W - LN + 1))
                snr = bersama.uniform(0.0, 10.0) if sp != "test" else 5.0
                while True:
                    p, ch = int(acak.choice(ids[sp])), int(acak.integers(0, seg.shape[2]))
                    if ok[p, ch]:
                        break
                n = seg[p, :, ch]
                c = X[r].astype(np.float64); cw = c[o:o + LN]
                g = np.sqrt(np.mean(cw ** 2) / (np.mean(n ** 2) * 10 ** (snr / 10)))
                noisy = c.copy(); noisy[o:o + LN] += g * n
                s = float(np.percentile(np.abs(noisy), 99.5)) + 1e-8
                Xn[j, :, 0] = noisy / s; Xc[j, :, 0] = c / s; sc[j] = s
            np.save(f"{d}/X_{sp}_noisy.npy", Xn); np.save(f"{d}/X_{sp}_clean.npy", Xc)
            np.save(f"{d}/valid_{sp}.npy", np.ones(N, bool)); np.save(f"{d}/scale_{sp}.npy", sc)
            print(f"  {kind}/{sp}: {N:,} sampel")


if __name__ == "__main__":
    main()
