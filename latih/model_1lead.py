"""Arsitektur model 1 lead, sama dengan TRAINING_V4 dan TRAINING_MULTITASK_B_V4 (Zaskia), NL = 1."""
from tensorflow.keras import Model, layers

W, NL = 768, 1
KINDS = ("bw", "ma", "em")          # urutan kelas multitask: 0 = BW, 1 = MA, 2 = EM


def cdae():
    """CDAE pembersih per jenis noise (yang dipakai lib/cdae.dart)."""
    inp = layers.Input((W, NL), name="input_ecg")
    x = layers.Conv1D(32, 5, strides=2, padding="same", activation="relu")(inp)
    x = layers.Conv1D(64, 5, strides=2, padding="same", activation="relu")(x)
    x = layers.Conv1D(64, 5, padding="same", activation="relu")(x)
    x = layers.Conv1D(64, 5, padding="same", dilation_rate=2, activation="relu")(x)
    x = layers.UpSampling1D(2)(x); x = layers.Conv1D(64, 5, padding="same", activation="relu")(x)
    x = layers.UpSampling1D(2)(x); x = layers.Conv1D(32, 5, padding="same", activation="relu")(x)
    out = layers.Conv1D(NL, 5, padding="same", activation="linear", name="output_ecg")(x)
    return Model(inp, out, name="CDAE_AE")


def multitask():
    """CDAE + kepala klasifikasi jenis noise (desain B: jenis noise memandu decoder)."""
    inp = layers.Input((W, NL), name="input_ecg")
    x = layers.Conv1D(32, 5, strides=2, padding="same", activation="relu")(inp)
    x = layers.Conv1D(64, 5, strides=2, padding="same", activation="relu")(x)
    for d in (1, 2):
        x = layers.Conv1D(64, 5, padding="same", dilation_rate=d, activation="relu")(x)
    z = x
    c = layers.Concatenate()([layers.GlobalAveragePooling1D()(z), layers.GlobalMaxPooling1D()(z)])
    c = layers.BatchNormalization()(c)
    c = layers.Dense(32, activation="relu")(c); c = layers.Dropout(0.2)(c)
    cls = layers.Dense(3, activation="softmax", name="noise_cls")(c)
    g = layers.RepeatVector(z.shape[1])(cls)
    y = layers.Concatenate()([z, g])
    y = layers.UpSampling1D(2)(y); y = layers.Conv1D(64, 5, padding="same", activation="relu")(y)
    y = layers.UpSampling1D(2)(y); y = layers.Conv1D(32, 5, padding="same", activation="relu")(y)
    out = layers.Conv1D(NL, 5, padding="same", activation="linear", name="output_ecg")(y)
    return Model(inp, [out, cls], name="CDAE_MTB")
