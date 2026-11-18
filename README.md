# Deteksi Artefak EKG (prototipe)

Satu layar Flutter web:
- deteksi segmen artefak (gerak, otot/elektroda, drift baseline) per blok 2 detik, dengan waktu mulai dan selesai;
- deteksi puncak R dengan Pan-Tompkins, hanya di bagian bersih;
- dasbor heart rate (beat, HR max/min/rata-rata, takikardia >100, bradikardia <60). Interval R-R yang menyeberangi artefak tidak dihitung.

Muat CSV sendiri (1 kolom amplitudo, atau `waktu,amplitudo`) dan isi fs. File diproses di browser, tidak diunggah ke mana pun.

Model aritmia: `abstract class ModelAritmia` di `lib/ekg.dart` adalah titik sambung untuk model klasifikasi (mis. ekspor TFLite/ONNX, atau API Python) yang dijalankan hanya pada beat di segmen bersih.

Build dan terbit otomatis lewat GitHub Actions ke GitHub Pages.
