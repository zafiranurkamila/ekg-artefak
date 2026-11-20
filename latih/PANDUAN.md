# Melatih model 1 lead di PC rumah (GPU)

Alat CardioSense single lead, sekitar 267 Hz. Model Zaskia dilatih 12 lead, jadi dilatih ulang 1 lead (lead II).
Aplikasi otomatis meresample 267 -> 257 Hz.

## Sekali saja: siapkan WSL2 + GPU
1. Pasang driver NVIDIA terbaru di Windows.
2. PowerShell (Admin): `wsl --install`, lalu restart dan buka Ubuntu.
3. Di Ubuntu:
```bash
sudo apt update && sudo apt install -y python3-venv git wget
python3 -m venv ~/ekg-env && source ~/ekg-env/bin/activate
pip install "tensorflow[and-cuda]" wfdb scipy numpy h5py
python -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
```
Kalau daftar GPU kosong, TensorFlow belum mendukung kartu ini; tanyakan ke AI untuk memakai Keras dengan backend PyTorch.

## Data (PhysioNet, gratis)
```bash
mkdir -p ~/ekg/data && cd ~/ekg/data
wget -r -N -c -np -nH --cut-dirs=3 -P incartdb https://physionet.org/files/incartdb/1.0.0/
wget -r -N -c -np -nH --cut-dirs=3 -P nstdb https://physionet.org/files/nstdb/1.0.0/
cd ~/ekg && git clone https://github.com/zafiranurkamila/ekg-artefak.git
```

## Jalankan berurutan (dari ~/ekg/ekg-artefak, venv aktif)
```bash
source ~/ekg-env/bin/activate && cd ~/ekg/ekg-artefak && git pull
python latih/prapemrosesan_1lead.py --incart ~/ekg/data/incartdb --nstdb ~/ekg/data/nstdb --keluar ~/ekg/data/processed_1lead
python latih/latih_1lead.py --data ~/ekg/data/processed_1lead --model cdae
python latih/latih_1lead.py --data ~/ekg/data/processed_1lead --model multitask
python tools/ekspor_bobot.py
python tools/mtb_numpy.py
git add model assets/model && git commit -m "Model 1 lead" && git push
```
Setelah push, GitHub Actions membangun ulang web dan aplikasi memakai model 1 lead.
Model multitask (jenis noise) belum disambung di aplikasi; minta AI menyambungkan `assets/model/mtb.bin`
ke `lib/` (lihat `tools/mtb_numpy.py` untuk urutan bobot dan forward pass).

## Kalau error
- Salin pesan error lengkap ke AI, sebut juga perintah yang dijalankan.
- Skrip prapemrosesan belum diuji di data penuh; kalau gagal, perbaiki di sana lalu push.
