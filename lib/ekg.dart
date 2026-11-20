// Logika EKG murni (tanpa Flutter): sinyal contoh, deteksi artefak,
// Pan-Tompkins, dan statistik detak jantung yang mengabaikan bagian artefak.
import 'dart:math';
import 'dart:typed_data';
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

/// Klasifikasi beat berbasis aturan (penanda awal; klasifikasi aritmia sebenarnya
/// dikerjakan tahap machine learning). Tiap detak dibandingkan dengan templat
/// (median semua detak, jendela QRS +-0,1 s):
/// - PVC: bentuk berbeda (korelasi < 0,7) dan datang lebih awal atau diikuti jeda panjang.
/// - PAC: bentuk normal, datang lebih awal (< 85% R-R median), lalu diikuti jeda lebih panjang.
/// Diuji pada INCART I01: kedua PVC beranotasi (2,76 s dan 10,33 s) terdeteksi.
List<String> klasifikasiBeat(List<double> y, double fs, List<int> r) {
  final n = y.length, w = (0.1 * fs).round();
  final pakai = [for (final i in r) i - w >= 0 && i + w < n];
  final idx = [for (var k = 0; k < r.length; k++) if (pakai[k]) k];
  if (idx.length < 3 || r.length < 3) return List.filled(r.length, 'N');
  final tpl = List<double>.generate(2 * w, (j) {
    final v = [for (final k in idx) y[r[k] - w + j]]..sort();
    return v[v.length ~/ 2];
  });
  double korelasi(int i) {
    var ma = 0.0, mb = 0.0;
    for (var j = 0; j < 2 * w; j++) {
      ma += y[i - w + j];
      mb += tpl[j];
    }
    ma /= 2 * w;
    mb /= 2 * w;
    var sab = 0.0, saa = 0.0, sbb = 0.0;
    for (var j = 0; j < 2 * w; j++) {
      final da = y[i - w + j] - ma, db = tpl[j] - mb;
      sab += da * db;
      saa += da * da;
      sbb += db * db;
    }
    return sab / (sqrt(saa * sbb) + 1e-12);
  }

  final rr = [for (var k = 1; k < r.length; k++) (r[k] - r[k - 1]) / fs]..sort();
  final med = rr[rr.length ~/ 2];
  return [
    for (var k = 0; k < r.length; k++)
      () {
        if (!pakai[k]) return 'N';
        final c = korelasi(r[k]);
        final sebelum = k > 0 ? (r[k] - r[k - 1]) / fs : med;
        final sesudah = k + 1 < r.length ? (r[k + 1] - r[k]) / fs : med;
        final dini = sebelum < 0.85 * med;
        if (c < 0.7 && (dini || sesudah > 1.15 * med || k == r.length - 1)) return 'PVC';
        if (c >= 0.7 && dini && sesudah > 1.1 * sebelum) return 'PAC';
        return 'N';
      }()
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
/// Deteksi waktu mulai dan selesai artefak, resolusi 0,1 detik.
/// Semua ambang relatif terhadap rekaman itu sendiri (bukan angka tetap),
/// sudah diuji pada INCART + noise NSTDB (em, ma, bw) dan pada sinyal contoh.
/// Jendela 0,25 s digeser tiap 0,1 s, dianggap noise bila:
/// - banyak titik balik besar (>= 6) pada sinyal tanpa garis dasar lambat;
///   "besar" = lebih dari 3x lantai noise (median |selisih antar-sampel|), atau
/// - garis dasar lokal (median 0,3 s) menyimpang dari garis dasar 2 s
///   lebih dari 25% tinggi QRS tipikal (baseline wander / elektroda bergeser).
/// Bagian noise yang berjarak < 0,4 s digabung, lalu diberi jarak aman 0,15 s.
List<Segmen> deteksiArtefak(List<double> x, double fs) {
  final n = x.length;
  // garis dasar lambat: rata-rata bergerak 1 s (tengah)
  final m1 = fs.round();
  final pref = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    pref[i + 1] = pref[i] + x[i];
  }
  final y = List<double>.generate(n, (i) {
    final a = max(0, i - m1 ~/ 2), z = min(n, i + m1 ~/ 2 + 1);
    return x[i] - (pref[z] - pref[a]) / (z - a);
  });
  double persentil(List<double> v, double p) {
    final u = [...v]..sort();
    return u[(p * (u.length - 1)).round()];
  }

  final tinggi = persentil(y.map((v) => v.abs()).toList(), 0.99);
  final dy = List<double>.generate(n - 1, (i) => y[i + 1] - y[i]);
  final lantai = persentil(dy.map((v) => v.abs()).toList(), 0.5);
  final ambang = max(3 * lantai, 0.02 * tinggi);
  double median(int a, int z) => persentil(x.sublist(max(0, a), min(n, z)), 0.5);

  final w = (0.25 * fs).round(), hop = (0.1 * fs).round();
  final tandai = List<bool>.filled(n, false);
  for (var a = 0; a + w <= n; a += hop) {
    var balik = 0, arahLalu = 0;
    for (var i = a; i < a + w - 1; i++) {
      if (dy[i].abs() < ambang) continue;
      final arah = dy[i] > 0 ? 1 : -1;
      if (arahLalu != 0 && arah != arahLalu) balik++;
      arahLalu = arah;
    }
    final p = a + w ~/ 2;
    final simpang = (median(p - (0.15 * fs).round(), p + (0.15 * fs).round()) - median(p - fs.round(), p + fs.round())).abs() /
        (tinggi + 1e-9);
    if (balik >= 6 || simpang > 0.25) {
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
/// Pan-Tompkins pada sinyal yang sudah difilter:
/// band-pass 5-15 Hz (maju-mundur), turunan 5 titik, kuadrat, integrasi jendela
/// 0,15 s yang terpusat (tanpa tertinggal), ambang 30% persentil-98.
/// Puncak R dicari +-75 ms dari puncak energi. Kandidat < 0,4 s setelah R sebelumnya
/// dibuang bila kemiringan < 70% atau amplitudo < 70% detak sebelumnya (gelombang T).
/// Diuji pada INCART I01 (31 detak beranotasi): 31 benar, 2 palsu, 0 terlewat.
List<int> panTompkins(List<double> y, double fs) {
  final n = y.length;
  if (n < fs) return [];
  final bp = _majuMundur(_majuMundur(y, _biquad('hp', 5, 0.7071, fs)), _biquad('lp', 15, 0.7071, fs));
  final d = List<double>.filled(n, 0);
  for (var i = 2; i < n - 2; i++) {
    d[i] = (-bp[i - 2] - 2 * bp[i - 1] + 2 * bp[i + 1] + bp[i + 2]) * fs / 8;
  }
  final h = (0.15 * fs).round() ~/ 2;
  final pref = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    pref[i + 1] = pref[i] + d[i] * d[i];
  }
  final mwi = List<double>.generate(n, (i) {
    final a = max(0, i - h), z = min(n, i + h + 1);
    return (pref[z] - pref[a]) / (z - a);
  });
  final urut = [...mwi]..sort();
  final ambang = 0.3 * urut[min(n - 1, (n * 0.98).floor())];
  final w = (0.075 * fs).round(), h1 = (fs / 2).round();
  double median(List<double> v) {
    final u = [...v]..sort();
    return u[u.length ~/ 2];
  }

  final puncak = <int>[], miring = <double>[], tinggi = <double>[];
  for (var i = 1; i < n - 1; i++) {
    if (!(mwi[i] > mwi[i - 1] && mwi[i] >= mwi[i + 1]) || mwi[i] < ambang) continue;
    final a = max(0, i - w), z = min(n, i + w + 1);
    final dasar = median(y.sublist(max(0, i - h1), min(n, i + h1)));
    var r = a;
    var m = 0.0;
    for (var j = a; j < z; j++) {
      if ((y[j] - dasar).abs() > (y[r] - dasar).abs()) r = j;
      m = max(m, d[j].abs());
    }
    final t = (y[r] - dasar).abs();
    if (puncak.isNotEmpty && r - puncak.last < (0.25 * fs).round()) {
      if (m > miring.last) {
        puncak[puncak.length - 1] = r;
        miring[miring.length - 1] = m;
        tinggi[tinggi.length - 1] = t;
      }
      continue;
    }
    if (puncak.isNotEmpty) {
      final acuanT = median(tinggi.sublist(max(0, tinggi.length - 8)));
      final acuanM = median(miring.sublist(max(0, miring.length - 8)));
      if (r - puncak.last < (0.4 * fs).round() && (m < 0.7 * miring.last || t < 0.7 * acuanT)) continue;
      if (t < 0.4 * acuanT && m < 0.5 * acuanM) continue;
    }
    puncak.add(r);
    miring.add(m);
    tinggi.add(t);
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

// ---------------------------------------------------------------- filter Zaskia
/// Filter yang sama dengan prapemrosesan Zaskia: band-pass 0,5-40 Hz dan notch 50 Hz.
/// Dijalankan maju lalu mundur (tanpa geser fase), ujung rekaman dipantulkan supaya
/// tidak ada lonjakan di awal dan akhir. Hasilnya garis dasar lurus (baseline wander
/// hilang), noise listrik 50 Hz hilang, dan sinyal lebih halus.
List<List<double>> _biquad(String jenis, double f0, double q, double fs) {
  final w = 2 * pi * f0 / fs, c = cos(w), al = sin(w) / (2 * q);
  final b = switch (jenis) {
    'hp' => [(1 + c) / 2, -(1 + c), (1 + c) / 2],
    'lp' => [(1 - c) / 2, 1 - c, (1 - c) / 2],
    _ => [1.0, -2 * c, 1.0],
  };
  final a0 = 1 + al;
  return [
    [b[0] / a0, b[1] / a0, b[2] / a0],
    [1.0, -2 * c / a0, (1 - al) / a0],
  ];
}

List<double> _lewat(List<double> v, List<List<double>> ba) {
  final b = ba[0], a = ba[1];
  final g = (b[0] + b[1] + b[2]) / (a[0] + a[1] + a[2]);
  var x1 = v[0], x2 = v[0], y1 = v[0] * g, y2 = v[0] * g;
  final out = List<double>.filled(v.length, 0);
  for (var i = 0; i < v.length; i++) {
    final o = b[0] * v[i] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2;
    x2 = x1;
    x1 = v[i];
    y2 = y1;
    y1 = o;
    out[i] = o;
  }
  return out;
}

/// Filter maju lalu mundur (tanpa geser fase).
List<double> _majuMundur(List<double> v, List<List<double>> ba) =>
    _lewat(_lewat(v, ba).reversed.toList(), ba).reversed.toList();

List<double> filterZaskia(List<double> x, double fs) {
  final n = x.length;
  if (n < 8) return [...x];
  final p = min(n - 1, (2 * fs).round());
  var v = <double>[
    for (var i = p; i >= 1; i--) 2 * x[0] - x[i],
    ...x,
    for (var i = n - 2; i >= n - 1 - p; i--) 2 * x[n - 1] - x[i],
  ];
  final tahap = [_biquad('hp', 0.5, 0.7071, fs)];
  if (40 < 0.45 * fs) tahap.add(_biquad('lp', 40, 0.7071, fs));
  if (50 < 0.45 * fs) tahap.add(_biquad('notch', 50, 30, fs));
  for (final ba in tahap) {
    v = _majuMundur(v, ba);
  }
  final y = v.sublist(p, p + n);
  final urut = [...y]..sort();
  final tengah = urut[n ~/ 2];
  return [for (final e in y) e - tengah];
}

// ---------------------------------------------------------------- keparahan
/// Tingkat tiap segmen artefak, diukur pada sinyal yang sudah difilter:
/// rasio puncak (persentil 99 |y|) segmen terhadap bagian bersih rekaman.
/// - 'lurus'  (< 1,0 dan tidak lagi terdeteksi setelah filter): sudah diluruskan filter
///   (biasanya baseline wander), tetap dihitung
/// - 'ringan' (1,0-1,4): direkonstruksi decoder CDAE bila model aktif, selain itu dibuang
/// - 'parah'  (>= 1,4): dibuang
/// Ambang diuji pada INCART + noise NSTDB 0 dB (ringan) dan -6 dB (parah).
List<String> tingkatArtefak(List<double> y, double fs, List<Segmen> art) {
  if (art.isEmpty) return const [];
  // artefak yang masih terdeteksi setelah filter (noise frekuensi tinggi tidak hilang oleh filter)
  final sisa = deteksiArtefak(y, fs);
  double p99(Iterable<double> v) {
    final u = v.map((e) => e.abs()).toList()..sort();
    return u.isEmpty ? 0 : u[(0.99 * (u.length - 1)).round()];
  }

  final bersih = <double>[];
  for (var i = 0; i < y.length; i++) {
    if (!art.any((s) => s.memuat(i / fs))) bersih.add(y[i]);
  }
  final acuan = bersih.length > fs ? p99(bersih) : p99(y);
  return [
    for (final s in art)
      () {
        final a = (s.mulai * fs).round(), z = min(y.length, (s.selesai * fs).round());
        final r = p99(y.sublist(a, max(a + 1, z))) / (acuan + 1e-9);
        final masihAda = sisa.any((t) => t.mulai < s.selesai && t.selesai > s.mulai);
        if (r < 1.0 && !masihAda) return 'lurus';
        return r < 1.4 ? 'ringan' : 'parah';
      }()
  ];
}

// ---------------------------------------------------------------- jenis noise
/// Posisi awal jendela [L] sampel yang menutupi rentang [a, z) pada sinyal sepanjang [n].
List<int> _jendelaSegmen(int a, int z, int n, int L) {
  if (n < L) return const [];
  final mulai = <int>[];
  if (z - a <= L - 64) {
    mulai.add(((a + z) ~/ 2 - L ~/ 2).clamp(0, n - L));
  } else {
    for (var m = max(0, a - 32);; m += L - 128) {
      final mm = min(m, n - L);
      mulai.add(mm);
      if (mm + L >= min(n, z + 32)) break;
    }
  }
  return mulai;
}

/// Jenis noise tiap segmen dari model multitask (kepala klasifikasi MTB-CDAE).
/// Masukan model = rekaman mentah tanpa noise listrik 50 Hz (BW/MA/EM tidak boleh
/// ikut terbuang filter 0,5-40 Hz), di-resample ke 257 Hz, jendela 768 sampel
/// dikurangi mediannya. Peluang [BW, MA, EM] dirata-rata atas jendela yang menutupi segmen.
/// Label: kelas teratas, ditambah kelas lain yang peluangnya >= 0,3 (noise campuran).
(List<List<String>>, List<List<double>>) jenisNoiseModel(List<double> x, double fs, List<Segmen> art, Mtb mtb) {
  if (art.isEmpty) return (const [], const []);
  final v = 50 < 0.45 * fs ? _majuMundur(x, _biquad('notch', 50, 30, fs)) : x;
  final x257 = resample(v, fs, Cdae.fs);
  const L = Cdae.jendela;
  final label = <List<String>>[], peluang = <List<double>>[];
  for (final s in art) {
    final a = (s.mulai * Cdae.fs).floor(), z = min(x257.length, (s.selesai * Cdae.fs).ceil());
    final p = [0.0, 0.0, 0.0];
    var k = 0;
    for (final m in _jendelaSegmen(a, z, x257.length, L)) {
      final w = x257.sublist(m, m + L);
      final med = ([...w]..sort())[L ~/ 2];
      final q = mtb.klasifikasi([for (final e in w) e - med]);
      for (var c = 0; c < 3; c++) {
        p[c] += q[c];
      }
      k++;
    }
    if (k == 0) {
      label.add(const ['Tidak pasti']);
      peluang.add(const []);
      continue;
    }
    for (var c = 0; c < 3; c++) {
      p[c] /= k;
    }
    final urut = [0, 1, 2]..sort((i, j) => p[j].compareTo(p[i]));
    label.add([for (final (r, c) in urut.indexed) if (r == 0 || p[c] >= 0.3) Mtb.kelas[c]]);
    peluang.add(p);
  }
  return (label, peluang);
}

/// Jenis noise berbasis aturan ciri sinyal. Hanya cadangan bila model multitask
/// (assets/model/mtb.bin) gagal dimuat:
/// - BW (baseline wander): komponen < 0,5 Hz besar, atau segmen sudah diluruskan filter
/// - MA (otot): energi > 40 Hz minimal 1,6x bagian bersih
/// - EM (elektroda): energi di pita EKG minimal 1,35x bagian bersih
/// - Listrik: energi 50 Hz minimal 2x bagian bersih
/// Diuji pada INCART + NSTDB: MA dan EM umumnya terbaca benar, BW di 0 dB lemah.
List<List<String>> jenisNoise(List<double> x, List<double> y, double fs, List<Segmen> art, List<String> tingkat) {
  if (art.isEmpty) return const [];
  final hp = _majuMundur(x, _biquad('hp', 0.5, 0.7071, fs));
  final rendah = [for (var i = 0; i < x.length; i++) x[i] - hp[i]];
  final atas = 40 < 0.45 * fs ? _majuMundur(hp, _biquad('lp', 40, 0.7071, fs)) : hp;
  final tinggi = [for (var i = 0; i < x.length; i++) hp[i] - atas[i]];
  final tanpa50 = 50 < 0.45 * fs ? _majuMundur(hp, _biquad('notch', 50, 30, fs)) : hp;
  final listrik = [for (var i = 0; i < x.length; i++) hp[i] - tanpa50[i]];
  final bersih = [for (var i = 0; i < x.length; i++) !art.any((s) => s.memuat(i / fs))];
  double rms(List<double> v, int a, int z, [bool hanyaBersih = false]) {
    var s = 0.0, c = 0;
    for (var i = a; i < z; i++) {
      if (hanyaBersih && !bersih[i]) continue;
      s += v[i] * v[i];
      c++;
    }
    return c == 0 ? 0 : sqrt(s / c);
  }

  final n = x.length;
  final cukup = bersih.where((b) => b).length > fs;
  final rT = rms(tinggi, 0, n, cukup), rY = rms(y, 0, n, cukup), rL = rms(listrik, 0, n, cukup);
  final absBersih = [for (var i = 0; i < n; i++) if (!cukup || bersih[i]) y[i].abs()]..sort();
  final acuan = absBersih.isEmpty ? 1.0 : absBersih[(0.99 * (absBersih.length - 1)).round()];
  return [
    for (final (k, s) in art.indexed)
      () {
        final a = (s.mulai * fs).round(), z = max(a + 2, min(n, (s.selesai * fs).round()));
        final l = rendah.sublist(a, z)..sort();
        final bw = (l[(0.99 * (l.length - 1)).round()] - l[(0.01 * (l.length - 1)).round()]) / (acuan + 1e-9);
        final j = <String>[];
        if (bw >= 0.6 || tingkat[k] == 'lurus') j.add('BW');
        if (rms(tinggi, a, z) >= 1.6 * rT) j.add('MA');
        if (tingkat[k] != 'lurus' && rms(y, a, z) >= 1.35 * rY) j.add('EM');
        if (rms(listrik, a, z) >= 2 * rL && rL > 0) j.add('Listrik');
        return j.isEmpty ? ['Tidak pasti'] : j;
      }()
  ];
}

// ---------------------------------------------------------------- aritmia berbahaya
/// Peringatan berbasis aturan dari detak yang terdeteksi. Klasifikasi aritmia yang
/// sebenarnya dikerjakan tahap machine learning; ini hanya penanda awal.
/// Detak di dalam segmen artefak (termasuk yang direkonstruksi) tidak dipakai,
/// supaya noise tidak memicu peringatan.
List<String> aritmiaBerbahaya(List<int> r, List<String> jenis, double fs, List<Segmen> dibuang) {
  final out = <String>[];
  var deret = 0, maks = 0;
  for (var k = 0; k < r.length; k++) {
    if (dibuang.any((s) => s.memuat(r[k] / fs))) {
      deret = 0;
      continue;
    }
    deret = jenis[k] == 'PVC' ? deret + 1 : 0;
    maks = max(maks, deret);
  }
  if (maks >= 3) out.add('$maks PVC berturut-turut (dugaan VT)');
  bool bersih(double a, double b) => !dibuang.any((s) => a < s.selesai && b > s.mulai);
  final rr = <double>[];
  for (var i = 1; i < r.length; i++) {
    final a = r[i - 1] / fs, b = r[i] / fs;
    if (bersih(a, b)) rr.add(b - a);
  }
  final jeda = rr.where((v) => v > 3).length;
  if (jeda > 0) out.add('Jeda lebih dari 3 detik ($jeda kali)');
  for (var i = 0; i + 4 < rr.length; i++) {
    final hr = 60 / (rr.sublist(i, i + 5).reduce((a, b) => a + b) / 5);
    if (hr > 150) {
      out.add('Detak sangat cepat (> 150 bpm)');
      break;
    }
  }
  for (var i = 0; i + 4 < rr.length; i++) {
    final hr = 60 / (rr.sublist(i, i + 5).reduce((a, b) => a + b) / 5);
    if (hr < 40) {
      out.add('Detak sangat lambat (< 40 bpm)');
      break;
    }
  }
  return out;
}

// ---------------------------------------------------------------- analisis
class HasilAnalisis {
  final List<double> sinyal; // sesudah filter (dan rekonstruksi bila ada)
  final List<double> sinyalAsli; // rekaman mentah
  final double fs;
  final List<Segmen> artefak;
  final List<String> tingkat; // per segmen: 'lurus' / 'ringan' / 'parah'
  final List<List<String>> jenis; // per segmen: BW / MA / EM (model multitask) atau aturan cadangan
  final List<List<double>> peluangJenis; // per segmen: peluang [BW, MA, EM] dari model; kosong bila aturan
  final List<String> penanganan; // per segmen, untuk ditampilkan
  final List<Segmen> dibuang; // segmen yang tidak dihitung
  final List<int> puncakR;
  final Statistik stat;
  final Statistik statSebelum; // detak dari seluruh rekaman, artefak ikut dihitung (60/T semua interval)
  final List<String> jenisBeat;
  final List<String> bahaya;
  const HasilAnalisis(this.sinyal, this.sinyalAsli, this.fs, this.artefak, this.tingkat, this.jenis, this.penanganan, this.dibuang,
      this.puncakR, this.stat, this.jenisBeat, this.bahaya, this.statSebelum, [this.peluangJenis = const []]);
  bool get jenisDariModel => peluangJenis.isNotEmpty;
  bool get dibersihkan => penanganan.any((p) => p.startsWith('Direkonstruksi'));
  /// Jumlah detak berjenis [j], tanpa detak di dalam segmen artefak.
  int hitung(String j) => [
        for (var k = 0; k < puncakR.length; k++)
          if (jenisBeat[k] == j && !artefak.any((s) => s.memuat(puncakR[k] / fs))) k
      ].length;
}

/// Alur lengkap:
/// 1. filter Zaskia (garis dasar lurus, tanpa 50 Hz, halus)
/// 2. deteksi waktu mulai/selesai artefak pada rekaman mentah
/// 3. tingkat tiap segmen: lurus / ringan / parah, jenis noise dari model multitask [mtb]
/// 4. ringan direkonstruksi decoder CDAE (bila [model] diisi), parah dibuang
/// 5. Pan-Tompkins di bagian yang dipakai, detak jantung tanpa bagian yang dibuang
HasilAnalisis analisis(List<double> x, double fs, {Map<String, Cdae> model = const {}, Mtb? mtb}) {
  final y = filterZaskia(x, fs);
  final art = deteksiArtefak(x, fs);
  final tingkat = tingkatArtefak(y, fs, art);
  final (jenisSeg, peluangSeg) = mtb != null && x.length >= Cdae.jendela * fs / Cdae.fs
      ? jenisNoiseModel(x, fs, art, mtb)
      : (jenisNoise(x, y, fs, art, tingkat), const <List<double>>[]);
  final sinyal = [...y];
  final penanganan = <String>[];
  final dibuang = <Segmen>[];
  final perluModel = <int>[];
  for (final (k, s) in art.indexed) {
    if (tingkat[k] == 'lurus') {
      penanganan.add('Diluruskan filter');
    } else if (tingkat[k] == 'ringan' && model.isNotEmpty) {
      perluModel.add(k);
      penanganan.add('');
    } else {
      penanganan.add('Dibuang');
      dibuang.add(s);
    }
  }
  if (perluModel.isNotEmpty && x.length >= 3 * fs) {
    final y257 = resample(y, fs, Cdae.fs);
    final hasil257 = [...y257];
    const L = Cdae.jendela;
    for (final k in perluModel) {
      final s = art[k];
      // decoder dipilih dari jenis noise (urutan label: peluang model tertinggi lebih dulu);
      // bila tidak ada yang cocok, aturan lama
      final jenis = [
            for (final e in jenisSeg[k])
              if (const {'MA', 'EM', 'BW'}.contains(e)) e.toLowerCase(),
          ].where(model.containsKey).firstOrNull ??
          pilihModel(x, fs, s, model.keys.toSet());
      penanganan[k] = 'Direkonstruksi ${jenis.toUpperCase()}';
      final a = (s.mulai * Cdae.fs).floor(), z = min(y257.length, (s.selesai * Cdae.fs).ceil());
      for (final m in _jendelaSegmen(a, z, y257.length, L)) {
        if (m + L > y257.length) continue;
        final keluar = model[jenis]!.bersihkan(y257.sublist(m, m + L));
        for (var i = max(a, m + 32); i < min(z, m + L - 32); i++) {
          hasil257[i] = keluar[i - m];
        }
      }
    }
    final balik = resample(hasil257, Cdae.fs, fs);
    for (final k in perluModel) {
      final s = art[k];
      for (var i = (s.mulai * fs).round(); i < min(sinyal.length, (s.selesai * fs).round()); i++) {
        if (i < balik.length) sinyal[i] = balik[i];
      }
    }
  } else {
    for (final k in perluModel) {
      penanganan[k] = 'Dibuang';
      dibuang.add(art[k]);
    }
    dibuang.sort((a, b) => a.mulai.compareTo(b.mulai));
  }

  // Pan-Tompkins terpisah di tiap bagian yang dipakai (>= 1,5 s)
  final r = <int>[];
  var awal = 0.0;
  for (final sg in [...dibuang, Segmen(x.length / fs, x.length / fs)]) {
    final m = (awal * fs).round(), z = (sg.mulai * fs).round();
    if (z - m >= 1.5 * fs) {
      for (final i in panTompkins(sinyal.sublist(m, z), fs)) {
        if ((m + i) / fs > awal + 0.2 || awal == 0) r.add(m + i); // lewati 0,2 s setelah bagian dibuang
      }
    }
    awal = sg.selesai;
  }
  // buang puncak sisipan palsu: terjepit di antara dua detak (kedua jarak < 0,6x R-R median)
  // dan jumlah kedua jaraknya ~1x median. PVC asli tidak begitu karena diikuti jeda kompensasi.
  while (r.length >= 4) {
    final rr = [for (var k = 1; k < r.length; k++) (r[k] - r[k - 1]) / fs]..sort();
    final med = rr[rr.length ~/ 2];
    int? buang;
    for (var k = 1; k < r.length - 1; k++) {
      final a = (r[k] - r[k - 1]) / fs, b = (r[k + 1] - r[k]) / fs;
      if (max(a, b) < 0.6 * med && a + b >= 0.8 * med && a + b <= 1.25 * med) {
        buang = k;
        break;
      }
    }
    if (buang == null) break;
    r.removeAt(buang);
  }
  final jenis = klasifikasiBeat(sinyal, fs, r);
  return HasilAnalisis(sinyal, x, fs, art, tingkat, jenisSeg, penanganan, dibuang, r, hitungStatistik(r, fs, dibuang), jenis,
      aritmiaBerbahaya(r, jenis, fs, art), hitungStatistik(panTompkins(y, fs), fs, const []), peluangSeg);
}

// ---------------------------------------------------------------- baca file
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

/// Baca .bin mentah: deretan float32 little-endian, satu lead (mV).
List<double> bacaBinFloat32(Uint8List b) {
  final d = ByteData.sublistView(b);
  return [
    for (var i = 0; i + 4 <= b.length; i += 4)
      if (d.getFloat32(i, Endian.little).isFinite) d.getFloat32(i, Endian.little)
  ];
}

/// Baca rekaman format PhysioNet (WFDB): isi file .hea dan bytes file .dat.
/// Mendukung format 16, 212, dan 80. Lead yang dipilih: II atau MLII, selain itu lead pertama.
/// Mengembalikan (sinyal mV, fs, nama lead).
(List<double>, double, String) bacaPhysionet(String hea, Uint8List dat) {
  final baris = hea.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty && !e.startsWith('#')).toList();
  if (baris.isEmpty) throw 'file .hea kosong';
  final kepala = baris.first.split(RegExp(r'\s+'));
  final nsig = int.parse(kepala[1]);
  final fs = kepala.length > 2 ? double.parse(kepala[2].split('/').first) : 250.0;
  final sinyal = baris.skip(1).take(nsig).map((e) => e.split(RegExp(r'\s+'))).toList();
  var lead = sinyal.indexWhere((t) => t.length > 8 && ['II', 'MLII'].contains(t.sublist(8).join(' ')));
  if (lead < 0) lead = 0;
  final t = sinyal[lead];
  final format = int.parse(RegExp(r'^\d+').firstMatch(t[1])!.group(0)!);
  var gain = 200.0, dasar = 0.0;
  if (t.length > 2) {
    final m = RegExp(r'^([\d.eE+-]+)(?:\(([-\d]+)\))?').firstMatch(t[2]);
    if (m != null) {
      gain = double.tryParse(m.group(1)!) ?? 200;
      if (gain == 0) gain = 200;
      if (m.group(2) != null) {
        dasar = double.parse(m.group(2)!);
      } else if (t.length > 4) {
        dasar = double.tryParse(t[4]) ?? 0;
      }
    }
  }
  final aliran = <int>[];
  if (format == 16) {
    final d = ByteData.sublistView(dat);
    for (var i = 0; i + 2 <= dat.length; i += 2) {
      aliran.add(d.getInt16(i, Endian.little));
    }
  } else if (format == 212) {
    int tanda(int v) => v >= 2048 ? v - 4096 : v;
    for (var i = 0; i + 3 <= dat.length; i += 3) {
      aliran.add(tanda(dat[i] | ((dat[i + 1] & 0x0F) << 8)));
      aliran.add(tanda(dat[i + 2] | ((dat[i + 1] & 0xF0) << 4)));
    }
  } else if (format == 80) {
    for (final v in dat) {
      aliran.add(v - 128);
    }
  } else {
    throw 'format $format belum didukung (hanya 16, 212, 80)';
  }
  final out = <double>[for (var i = lead; i < aliran.length; i += nsig) (aliran[i] - dasar) / gain];
  final nama = t.length > 8 ? t.sublist(8).join(' ') : 'lead ${lead + 1}';
  return (out, fs, nama);
}

/// Simpan sinyal sebagai float32 little-endian (untuk tahap machine learning).
Uint8List keBinFloat32(List<double> x) {
  final d = ByteData(x.length * 4);
  for (var i = 0; i < x.length; i++) {
    d.setFloat32(i * 4, x[i], Endian.little);
  }
  return d.buffer.asUint8List();
}
