"""Latih model 1 lead di GPU lokal.

  python latih/latih_1lead.py --data ~/ekg/data/processed_1lead --model cdae        # 3 model pembersih bw, ma, em
  python latih/latih_1lead.py --data ~/ekg/data/processed_1lead --model multitask   # 1 model pembersih + jenis noise

Pengaturan pelatihan sama dengan notebook Zaskia: Adam 1e-3 (clipnorm 1), batch 64,
maks 100 epoch, EarlyStopping patience 12, ReduceLROnPlateau, seed 42.
Multitask: loss = MSE sinyal + 0,01 x cross-entropy jenis noise.
Hasil: model/<jenis>_cdae_seed42_best.keras atau model/mtb_cdae_seed42_best.keras
"""
import argparse, json, os, sys
import numpy as np
import tensorflow as tf

sys.path.insert(0, os.path.dirname(__file__))
from model_1lead import KINDS, cdae, multitask

EPOCHS, BATCH, LR, PATIENCE, SEED = 100, 64, 1e-3, 12, 42


def callbacks(path):
    return [tf.keras.callbacks.TerminateOnNaN(),
            tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=PATIENCE, restore_best_weights=True),
            tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=4, min_lr=1e-5),
            tf.keras.callbacks.ModelCheckpoint(path, monitor="val_loss", save_best_only=True)]


def muat(d, kind, sp):
    return np.load(f"{d}/{kind}/X_{sp}_noisy.npy"), np.load(f"{d}/{kind}/X_{sp}_clean.npy")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True); ap.add_argument("--model", choices=["cdae", "multitask"], required=True)
    arg = ap.parse_args(); d = os.path.expanduser(arg.data)
    print("GPU:", tf.config.list_physical_devices("GPU") or "TIDAK ADA (akan sangat lambat)")
    os.makedirs("model", exist_ok=True)
    if arg.model == "cdae":
        for kind in KINDS:
            tf.keras.utils.set_random_seed(SEED)
            (xt, yt), (xv, yv) = muat(d, kind, "train"), muat(d, kind, "val")
            m = cdae(); m.compile(tf.keras.optimizers.Adam(LR, clipnorm=1.0), loss="mse")
            path = f"model/{kind}_cdae_seed{SEED}_best.keras"
            h = m.fit(xt, yt, validation_data=(xv, yv), epochs=EPOCHS, batch_size=BATCH, callbacks=callbacks(path), verbose=2)
            json.dump(h.history, open(path.replace("_best.keras", "_history.json"), "w"))
            print(kind, "selesai, val_loss terbaik", min(h.history["val_loss"]))
    else:
        tf.keras.utils.set_random_seed(SEED)
        def gabung(sp):
            xs, ys, cs = [], [], []
            for i, kind in enumerate(KINDS):
                x, y = muat(d, kind, sp); xs.append(x); ys.append(y); cs.append(np.full(len(x), i, np.int32))
            return np.concatenate(xs), {"output_ecg": np.concatenate(ys), "noise_cls": np.concatenate(cs)}
        (xt, yt), (xv, yv) = gabung("train"), gabung("val")
        m = multitask()
        m.compile(tf.keras.optimizers.Adam(LR, clipnorm=1.0),
                  loss={"output_ecg": "mse", "noise_cls": "sparse_categorical_crossentropy"},
                  loss_weights={"output_ecg": 1.0, "noise_cls": 0.01}, metrics={"noise_cls": "accuracy"})
        path = f"model/mtb_cdae_seed{SEED}_best.keras"
        h = m.fit(xt, yt, validation_data=(xv, yv), epochs=EPOCHS, batch_size=BATCH, shuffle=True,
                  callbacks=callbacks(path), verbose=2)
        json.dump(h.history, open(path.replace("_best.keras", "_history.json"), "w"))
        print("multitask selesai, akurasi jenis noise (val) terbaik", max(h.history["val_noise_cls_accuracy"]))


if __name__ == "__main__":
    main()
