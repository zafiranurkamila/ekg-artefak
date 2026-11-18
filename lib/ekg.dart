// Logika EKG murni (tanpa Flutter): sinyal contoh, deteksi artefak,
// Pan-Tompkins, dan statistik detak jantung yang mengabaikan bagian artefak.
import 'dart:math';
import 'cdae.dart';

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
  final List<String> jenisBeat; // 'N', 'PVC', atau 'PAC' untuk tiap puncak R
  final List<double>? sinyalAsli; // terisi bila artefak sudah dibersihkan model
  final Map<int, String> modelPerSegmen; // indeks segmen -> 'bw' / 'em'
  const HasilAnalisis(this.sinyal, this.fs, this.artefak, this.puncakR, this.stat, this.jenisBeat,
      {this.sinyalAsli, this.modelPerSegmen = const {}});
  bool get dibersihkan => sinyalAsli != null;
  int hitung(String j) => jenisBeat.where((e) => e == j).length;
}

/// Klasifikasi beat berbasis aturan (sementara, sebelum model AI dipasang):
/// - PVC: QRS lebar (>= 100 ms).
/// - PAC: QRS normal, datang lebih awal (R-R < 80% R-R sebelumnya)
///   lalu diikuti jeda lebih panjang. R-R > 2 s dianggap terputus artefak.
List<String> klasifikasiBeat(List<double> x, double fs, List<int> r) {
  final n = x.length;
  double lebarQrs(int i) {
    final jendela = x.sublist(max(0, i - (0.5 * fs).round()), min(n, i + (0.5 * fs).round()))..sort();
    final dasar = jendela[jendela.length ~/ 2];
    var amp = 0.0;
    for (var j = max(0, i - (0.05 * fs).round()); j < min(n, i + (0.05 * fs).round()); j++) {
      amp = max(amp, (x[j] - dasar).abs());
    }
    int? awal, akhir;
    for (var j = max(0, i - (0.12 * fs).round()); j < min(n, i + (0.12 * fs).round()); j++) {
      if ((x[j] - dasar).abs() > 0.3 * amp) {
        awal ??= j;
        akhir = j;
      }
    }
    return awal == null ? 0 : (akhir! - awal) / fs * 1000;
  }

  double? rr(int k) => k <= 0 || k >= r.length || (r[k] - r[k - 1]) / fs > 2 ? null : (r[k] - r[k - 1]) / fs;
  return [
    for (var k = 0; k < r.length; k++)
      if (lebarQrs(r[k]) >= 100)
        'PVC'
      else if (rr(k) != null && rr(k - 1) != null && rr(k)! < 0.8 * rr(k - 1)! && (rr(k + 1) ?? 0) > 1.15 * rr(k)!)
        'PAC'
      else
        'N'
  ];
}

// ---------------------------------------------------------------- sinyal contoh
/// Sinyal contoh yang meniru rekaman nyata: sinus lambat, PVC di akhir,
/// artefak gerak (1,1-4,0 s), artefak otot/elektroda (13,6-15,5 s),
/// dan baseline wander yang turun (15,3-16,6 s).
List<double> sinyalContoh({double fs = 250, double durasi = 20, int seed = 7}) {
  final r = Random(seed);
  final n = (fs * durasi).round();
  final x = List<double>.filled(n, 0);
  double g(double t, double c, double w, double a) => a * exp(-pow((t - c) / w, 2));
  final beats = <double>[0.25, 1.05, 1.9, 2.7, 3.5, 4.25, 5.05, 5.85, 7.3, 8.65, 10.0,
      11.3, 12.65, 16.7, 17.15, 17.6, 18.1, 18.95];
  for (final b in beats) {
    final pvc = (b - 18.95).abs() < 1e-6;
    for (var i = 0; i < n; i++) {
      final t = i / fs;
      if ((t - b).abs() > 0.6) continue;
      x[i] += pvc
          ? g(t, b, 0.03, 1.7) - g(t, b + 0.08, 0.05, 0.8) - g(t, b + 0.3, 0.08, 0.5)
          : g(t, b - 0.18, 0.03, 0.12) + g(t, b, 0.012, 1.5) - g(t, b + 0.03, 0.012, 0.25) + g(t, b + 0.25, 0.05, 0.3);
    }
  }
  // noise acak yang sedikit dihaluskan supaya mirip rekaman, bukan putih murni
  List<double> acak(double amp, int halus) {
    final v = List<double>.generate(n, (_) => (r.nextDouble() - .5) * 2 * amp);
    final o = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var s = 0.0, c = 0;
      for (var k = max(0, i - halus); k <= min(n - 1, i + halus); k++) {
        s += v[k];
        c++;
      }
      o[i] = s / c;
    }
    return o;
  }

  final hf = acak(2.2, 1), mf = acak(3.0, 4);
  double jendela(double t, double a, double z) =>
      t < a || t > z ? 0 : pow(max(0.0, sin(pi * (t - a) / (z - a))), 0.3).toDouble();
  for (var i = 0; i < n; i++) {
    final t = i / fs;
    x[i] += 0.015 * (r.nextDouble() - .5);
    // artefak gerak: naik lalu turun, dengan noise frekuensi tinggi
    final wg = jendela(t, 1.1, 4.0);
    if (wg > 0) x[i] += wg * (0.55 * hf[i] + 0.25 * mf[i] + 1.1 * sin(pi * (t - 1.1) / 1.45) - 0.4);
    // artefak otot/elektroda lepas
    final wo = jendela(t, 13.6, 15.5);
    if (wo > 0) x[i] += wo * (0.9 * hf[i] + 0.3 * mf[i]);
    // baseline wander: naik pelan lalu turun tajam, halus
    final wd = jendela(t, 15.3, 16.6);
    if (wd > 0) x[i] += wd * (1.4 * sin(pi * (t - 15.3) / 1.3) * (1 - (t - 15.3) / 1.3) - 2.0 * pow((t - 15.3) / 1.3, 3) + 0.08 * hf[i]);
  }
  return x;
}

// ---------------------------------------------------------------- artefak
/// Deteksi waktu mulai dan selesai artefak dengan resolusi 0,1 detik.
/// Jendela 0,25 s digeser tiap 0,1 s, dianggap noise bila:
/// - banyak titik balik besar (noise gerak/otot; QRS normal hanya 3-4 titik balik), atau
/// - garis dasar (median) menyimpang jauh dari garis dasar global (baseline wander).
/// Bagian noise yang berjarak < 0,4 s digabung, lalu diberi jarak aman 0,15 s.
List<Segmen> deteksiArtefak(List<double> x, double fs) {
  final n = x.length;
  final w = (0.25 * fs).round(), hop = (0.1 * fs).round();
  final glob = ([...x]..sort())[n ~/ 2];
  final ambangLangkah = 0.08; // mV per sampel pada 250 Hz
  final tandai = List<bool>.filled(n, false);
  for (var a = 0; a + w <= n; a += hop) {
    var balik = 0;
    var arahLalu = 0;
    for (var i = a + 1; i < a + w; i++) {
      final dlt = x[i] - x[i - 1];
      if (dlt.abs() < ambangLangkah * 250 / fs) continue;
      final arah = dlt > 0 ? 1 : -1;
      if (arahLalu != 0 && arah != arahLalu) balik++;
      arahLalu = arah;
    }
    final p = x.sublist(a, a + w)..sort();
    final geser = (p[w ~/ 2] - glob).abs();
    if (balik >= 8 || geser > 0.35) {
      for (var i = a; i < a + w; i++) {
        tandai[i] = true;
      }
    }
  }
  final seg = <Segmen>[];
  int? mulai;
  for (var i = 0; i <= n; i++) {
    final k = i < n && tandai[i];
    if (k && mulai == null) mulai = i;
    if (!k && mulai != null) {
      seg.add(Segmen(mulai / fs, i / fs));
      mulai = null;
    }
  }
  final gabung = <Segmen>[];
  for (final s in seg) {
    if (gabung.isNotEmpty && s.mulai - gabung.last.selesai < 0.4) {
      gabung[gabung.length - 1] = Segmen(gabung.last.mulai, s.selesai);
    } else {
      gabung.add(s);
    }
  }
  final durasi = n / fs;
  return gabung
      .where((s) => s.selesai - s.mulai >= 0.3)
      .map((s) => Segmen(max(0, s.mulai - 0.15), min(durasi, s.selesai + 0.15)))
      .toList();
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
  // ambang dari bagian ini sendiri: puncak MWI di atas 35% persentil-98,
  // periode refrakter 0,2 s
  final urut = [...mwi]..sort();
  final ambang = 0.35 * urut[(n * 0.98).floor().clamp(0, n - 1)];
  final refrakter = (0.2 * fs).round();
  final puncak = <int>[];
  final nilai = <double>[];
  for (var i = 1; i < n - 1; i++) {
    if (!(mwi[i] > mwi[i - 1] && mwi[i] >= mwi[i + 1]) || mwi[i] < ambang) continue;
    final a = max(0, i - (0.2 * fs).round()), z = min(n, i + (0.05 * fs).round());
    var best = a;
    for (var j = a; j < z; j++) {
      if (bp[j].abs() > bp[best].abs()) best = j;
    }
    if (puncak.isNotEmpty && best - puncak.last < refrakter) {
      if (mwi[i] > nilai.last) {
        puncak[puncak.length - 1] = best;
        nilai[nilai.length - 1] = mwi[i];
      }
      continue;
    }
    // gelombang T: muncul < 0,45 s setelah R dan energinya jauh lebih kecil
    if (puncak.isNotEmpty && best - puncak.last < 0.45 * fs && mwi[i] < 0.6 * nilai.last) continue;
    puncak.add(best);
    nilai.add(mwi[i]);
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
  // Pan-Tompkins dijalankan terpisah di tiap bagian bersih (>= 1,5 s)
  final r = <int>[];
  var awal = 0.0;
  final batas = [...art, Segmen(x.length / fs, x.length / fs)];
  for (final sg in batas) {
    final m = (awal * fs).round(), z = (sg.mulai * fs).round();
    if (z - m >= 1.5 * fs) {
      for (final i in panTompkins(x.sublist(m, z), fs)) {
        final t = (m + i) / fs;
        if (t > awal + 0.2 || awal == 0) r.add(m + i); // lewati 0,2 s pertama setelah artefak
      }
    }
    awal = sg.selesai;
  }
  return HasilAnalisis(x, fs, art, r, hitungStatistik(r, fs, art), klasifikasiBeat(x, fs, r));
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

/// Jenis model untuk satu segmen: 'bw' (baseline wander, perubahan lambat)
/// atau 'em' (elektroda/gerak, perubahan cepat). Model 'ma' menyusul.
String pilihModel(List<double> x, double fs, Segmen s, Set<String> tersedia) {
  final a = (s.mulai * fs).round(), z = min(x.length, (s.selesai * fs).round());
  var d = 0.0;
  for (var i = a + 1; i < z; i++) {
    d += (x[i] - x[i - 1]).abs();
  }
  final rata = d / max(1, z - a - 1) * fs / 250; // setara per sampel di 250 Hz
  final ingin = rata > 0.04 ? 'em' : 'bw';
  if (tersedia.contains(ingin)) return ingin;
  if (ingin == 'em' && tersedia.contains('ma')) return 'ma';
  return tersedia.first;
}

/// Bersihkan segmen artefak dengan model CDAE, lalu analisis ulang seluruh rekaman
/// (bagian yang sudah dibersihkan ikut dihitung).
HasilAnalisis analisisDenganModel(List<double> x, double fs, Map<String, Cdae> model) {
  final art = deteksiArtefak(x, fs);
  if (art.isEmpty || model.isEmpty) return analisis(x, fs);
  final x257 = resample(x, fs, Cdae.fs);
  final y257 = [...x257];
  const L = Cdae.jendela;
  final pilihan = <int, String>{};
  for (final (k, s) in art.indexed) {
    final jenis = pilihModel(x, fs, s, model.keys.toSet());
    pilihan[k] = jenis;
    final a = (s.mulai * Cdae.fs).floor(), z = min(x257.length, (s.selesai * Cdae.fs).ceil());
    // jendela 768 yang menutupi [a, z): satu jendela di tengah, atau beberapa bila segmen panjang
    final mulai = <int>[];
    if (z - a <= L - 64) {
      mulai.add(((a + z) ~/ 2 - L ~/ 2).clamp(0, max(0, x257.length - L)));
    } else {
      for (var m = max(0, a - 32); ; m += L - 128) {
        final mm = min(m, max(0, x257.length - L));
        mulai.add(mm);
        if (mm + L >= min(x257.length, z + 32)) break;
      }
    }
    for (final m in mulai) {
      if (m + L > x257.length) continue; // rekaman lebih pendek dari 3 detik
      final keluar = model[jenis]!.bersihkan(x257.sublist(m, m + L));
      // tulis hanya bagian dalam segmen, abaikan 32 sampel tepi jendela (efek padding)
      for (var i = max(a, m + 32); i < min(z, m + L - 32); i++) {
        y257[i] = keluar[i - m];
      }
    }
  }
  final balik = resample(y257, Cdae.fs, fs);
  final bersih = [...x];
  for (final s in art) {
    for (var i = (s.mulai * fs).round(); i < min(x.length, (s.selesai * fs).round()); i++) {
      if (i < balik.length) bersih[i] = balik[i];
    }
  }
  final r = panTompkins(bersih, fs);
  return HasilAnalisis(bersih, fs, art, r, hitungStatistik(r, fs, const []), klasifikasiBeat(bersih, fs, r),
      sinyalAsli: x, modelPerSegmen: pilihan);
}
