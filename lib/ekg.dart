// Logika EKG murni (tanpa Flutter): sinyal contoh, deteksi artefak,
// Pan-Tompkins, dan statistik detak jantung yang mengabaikan bagian artefak.
import 'dart:math';

class Segmen {
  final double mulai, selesai; // detik
  const Segmen(this.mulai, this.selesai);
  bool memuat(double t) => t >= mulai && t < selesai;
  @override
  String toString() => '${mulai.toStringAsFixed(1)}-${selesai.toStringAsFixed(1)} s';
}

class Statistik {
  final int totalBeat, tachy, brady, jumlahInterval;
  final double hrMax, hrMin, hrRata;
  const Statistik(this.totalBeat, this.hrMax, this.hrMin, this.hrRata, this.tachy,
      this.brady, this.jumlahInterval);
  double get persenTachy => jumlahInterval == 0 ? 0 : tachy * 100 / jumlahInterval;
  double get persenBrady => jumlahInterval == 0 ? 0 : brady * 100 / jumlahInterval;
}

class HasilAnalisis {
  final List<double> sinyal;
  final double fs;
  final List<Segmen> artefak;
  final List<int> puncakR; // indeks sampel, hanya di bagian bersih
  final Statistik stat;
  const HasilAnalisis(this.sinyal, this.fs, this.artefak, this.puncakR, this.stat);
}

/// Titik sambung untuk model aritmia (mis. model Zaskia).
/// Implementasi nanti bisa memanggil TFLite/ONNX atau server Python.
abstract class ModelAritmia {
  Future<String> klasifikasi(List<double> potonganBeat, double fs);
}

// ---------------------------------------------------------------- sinyal contoh
List<double> sinyalContoh({double fs = 250, double durasi = 20, int seed = 7}) {
  final r = Random(seed);
  final n = (fs * durasi).round();
  final x = List<double>.filled(n, 0);
  double g(double t, double c, double w, double a) => a * exp(-pow((t - c) / w, 2));
  // detak: sebagian lambat (bradikardia), satu PVC lebar
  final beats = <double>[0.25, 1.05, 1.9, 2.7, 3.5, 4.25, 5.05, 5.85, 7.3, 8.65, 10.0,
      11.3, 12.65, 16.7, 17.15, 17.6, 18.1, 18.95];
  for (final b in beats) {
    final pvc = (b - 18.95).abs() < 1e-6;
    for (var i = 0; i < n; i++) {
      final t = i / fs;
      if ((t - b).abs() > 0.6) continue;
      if (pvc) {
        x[i] += g(t, b, 0.03, 1.7) - g(t, b + 0.08, 0.05, 0.8) - g(t, b + 0.3, 0.08, 0.5);
      } else {
        x[i] += g(t, b - 0.18, 0.03, 0.12) + g(t, b, 0.012, 1.5) -
            g(t, b + 0.03, 0.012, 0.25) + g(t, b + 0.25, 0.05, 0.3);
      }
    }
  }
  for (var i = 0; i < n; i++) {
    final t = i / fs;
    x[i] += 0.02 * (r.nextDouble() - .5);
    if (t > 1.2 && t < 4.0) x[i] += 1.4 * (r.nextDouble() - .5) * 2 + (t > 2.5 ? -1.2 : 0.8); // gerak
    if (t > 13.6 && t < 15.5) x[i] += 2.6 * (r.nextDouble() - .5) * 2; // otot/elektroda
    if (t > 15.0 && t < 16.6) x[i] += 1.6 * sin(pi * (t - 15.0) / 3.2) - 2.2 * max(0, t - 15.9); // drift
  }
  return x;
}

// ---------------------------------------------------------------- artefak
/// Jendela 0,5 s. Jendela dianggap artefak bila energi turunan (frekuensi tinggi)
/// atau rentang amplitudo jauh di atas median sinyal, atau baseline bergeser.
/// Jendela artefak yang berdekatan digabung, lalu dibulatkan ke blok [blok] detik
/// supaya mulai/selesai artefak jelas seperti pada grafik referensi.
List<Segmen> deteksiArtefak(List<double> x, double fs, {double blok = 2.0}) {
  final w = (0.5 * fs).round();
  final jml = x.length ~/ w;
  final energi = <double>[], rentang = <double>[], baseline = <double>[];
  for (var k = 0; k < jml; k++) {
    final p = x.sublist(k * w, (k + 1) * w);
    var e = 0.0;
    for (var i = 1; i < p.length; i++) {
      e += pow(p[i] - p[i - 1], 2);
    }
    energi.add(e / p.length);
    final urut = [...p]..sort();
    rentang.add(urut[(p.length * .98).floor()] - urut[(p.length * .02).floor()]);
    baseline.add(urut[p.length ~/ 2]);
  }
  double med(List<double> v) => ([...v]..sort())[v.length ~/ 2];
  final mE = med(energi), mR = med(rentang);
  final kotor = List<bool>.generate(jml,
      (k) => energi[k] > 6 * mE || rentang[k] > 3 * mR || baseline[k].abs() > 0.4);
  // bulatkan ke blok
  final nBlok = (x.length / fs / blok).ceil();
  final hasil = <Segmen>[];
  for (var b = 0; b < nBlok; b++) {
    final a = (b * blok / 0.5).round(), z = min(jml, ((b + 1) * blok / 0.5).round());
    var c = 0;
    for (var k = a; k < z; k++) {
      if (kotor[k]) c++;
    }
    if (c >= 1) {
      final s = Segmen(b * blok, min((b + 1) * blok, x.length / fs));
      if (hasil.isNotEmpty && (hasil.last.selesai - s.mulai).abs() < 1e-9) {
        hasil[hasil.length - 1] = Segmen(hasil.last.mulai, s.selesai);
      } else {
        hasil.add(s);
      }
    }
  }
  return hasil;
}

// ---------------------------------------------------------------- Pan-Tompkins
List<int> panTompkins(List<double> x, double fs) {
  final n = x.length;
  // band-pass sederhana 5-15 Hz: high-pass (kurangi rata-rata bergerak) lalu low-pass
  List<double> rataGeser(List<double> v, int m) {
    final out = List<double>.filled(v.length, 0);
    var s = 0.0;
    for (var i = 0; i < v.length; i++) {
      s += v[i];
      if (i >= m) s -= v[i - m];
      out[i] = s / min(i + 1, m);
    }
    return out;
  }

  final lp = rataGeser(x, max(1, (fs / 30).round()));
  final base = rataGeser(lp, (fs / 5).round());
  final bp = List<double>.generate(n, (i) => lp[i] - base[i]);
  final d = List<double>.generate(n, (i) => i < 2 || i > n - 3
      ? 0
      : (-bp[i - 2] - 2 * bp[i - 1] + 2 * bp[i + 1] + bp[i + 2]) * fs / 8);
  final sq = d.map((v) => v * v).toList();
  final mwi = rataGeser(sq, (0.15 * fs).round());
  // ambang adaptif
  var spk = 0.0, npk = 0.0;
  final awal = mwi.sublist(0, min(n, (2 * fs).round()));
  spk = awal.reduce(max) * 0.25;
  npk = awal.reduce((a, b) => a + b) / awal.length * 0.5;
  final refrakter = (0.2 * fs).round();
  final puncak = <int>[];
  for (var i = 1; i < n - 1; i++) {
    if (!(mwi[i] > mwi[i - 1] && mwi[i] >= mwi[i + 1])) continue;
    final ambang = npk + 0.25 * (spk - npk);
    if (mwi[i] > ambang && (puncak.isEmpty || i - puncak.last > refrakter)) {
      // cari puncak R pada sinyal asli di sekitar (MWI tertunda ~ setengah jendela)
      final a = max(0, i - (0.2 * fs).round()), z = min(n, i + (0.05 * fs).round());
      var best = a;
      for (var j = a; j < z; j++) {
        if (bp[j].abs() > bp[best].abs()) best = j;
      }
      puncak.add(best);
      spk = 0.125 * mwi[i] + 0.875 * spk;
    } else {
      npk = 0.125 * mwi[i] + 0.875 * npk;
    }
  }
  return puncak;
}

// ---------------------------------------------------------------- statistik
Statistik hitungStatistik(List<int> r, double fs, List<Segmen> artefak) {
  bool bersih(double a, double b) => !artefak.any((s) => a < s.selesai && b > s.mulai);
  final hr = <double>[];
  for (var i = 1; i < r.length; i++) {
    final a = r[i - 1] / fs, b = r[i] / fs;
    if (bersih(a, b)) hr.add(60 / (b - a)); // interval yang menyeberangi artefak dibuang
  }
  if (hr.isEmpty) return Statistik(r.length, 0, 0, 0, 0, 0, 0);
  return Statistik(
    r.length,
    hr.reduce(max),
    hr.reduce(min),
    hr.reduce((a, b) => a + b) / hr.length,
    hr.where((v) => v > 100).length,
    hr.where((v) => v < 60).length,
    hr.length,
  );
}

HasilAnalisis analisis(List<double> x, double fs) {
  final art = deteksiArtefak(x, fs);
  final semua = panTompkins(x, fs);
  final r = semua.where((i) => !art.any((s) => s.memuat(i / fs))).toList();
  return HasilAnalisis(x, fs, art, r, hitungStatistik(r, fs, art));
}

/// Baca CSV satu kolom (amplitudo) atau dua kolom (waktu, amplitudo).
List<double> bacaCsv(String isi) {
  final out = <double>[];
  for (final baris in isi.split(RegExp(r'\r?\n'))) {
    final kol = baris.split(RegExp(r'[,;\t ]+')).where((s) => s.isNotEmpty).toList();
    if (kol.isEmpty) continue;
    final v = double.tryParse(kol.last);
    if (v != null) out.add(v);
  }
  return out;
}
