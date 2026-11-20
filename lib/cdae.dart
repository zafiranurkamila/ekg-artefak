// Model denoising CDAE dari Zaskia (TRAINING_V4), dijalankan langsung di Dart.
// Arsitektur (dari config.json):
//   Conv1D 32 k5 s2 relu -> Conv1D 64 k5 s2 relu -> Conv1D 64 k5 relu -> Conv1D 64 k5 d2 relu
//   -> UpSampling x2 -> Conv1D 64 k5 relu -> UpSampling x2 -> Conv1D 32 k5 relu -> Conv1D 12 k5 linear
// Masukan (768, 12) pada 257 Hz, diskalakan dengan persentil 99,5 dari |sinyal kotor|.
// Bobot diekspor oleh tools/ekspor_bobot.py ke assets/model/<jenis>.bin.
import 'dart:math';
import 'dart:typed_data';

class _Lapis {
  final Float32List k, b; // k: [5][masuk][keluar]
  final int masuk, keluar, langkah, dilasi;
  final bool relu;
  _Lapis(this.k, this.b, this.masuk, this.keluar, this.langkah, this.dilasi, this.relu);
}

class Cdae {
  static const fs = 257.0, jendela = 768;
  final int lead; // 12 (model lama) atau 1 (model 1 lead), dibaca dari ukuran bobot
  final List<_Lapis?> _lapis; // null = UpSampling x2

  Cdae._(this._lapis, this.lead);

  factory Cdae.dariBytes(ByteData data) {
    final w = data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4);
    var pos = 0;
    int ukuran(int l) => 5 * l * 32 + 32 + 2 * (5 * 64 * 64 + 64) + 5 * 32 * 64 + 64 + 5 * 64 * 64 + 64 + 5 * 64 * 32 + 32 + 5 * 32 * l + l;
    final nl = ukuran(1) == w.length ? 1 : 12;
    final spek = [
      [nl, 32, 2, 1, 1], [32, 64, 2, 1, 1], [64, 64, 1, 1, 1], [64, 64, 1, 2, 1], null,
      [64, 64, 1, 1, 1], null, [64, 32, 1, 1, 1], [32, nl, 1, 1, 0],
    ];
    final lapis = <_Lapis?>[];
    for (final s in spek) {
      if (s == null) {
        lapis.add(null);
        continue;
      }
      final nk = 5 * s[0] * s[1];
      final k = Float32List.sublistView(w, pos, pos + nk);
      pos += nk;
      final b = Float32List.sublistView(w, pos, pos + s[1]);
      pos += s[1];
      lapis.add(_Lapis(k, b, s[0], s[1], s[2], s[3], s[4] == 1));
    }
    if (pos != w.length) throw StateError('ukuran bobot tidak cocok ($pos vs ${w.length})');
    return Cdae._(lapis, nl);
  }

  /// x: data baris-utama panjang n*kanal. Padding 'same' mengikuti TensorFlow.
  static Float64List _conv(Float64List x, int n, _Lapis l) {
    final ke = 4 * l.dilasi + 1;
    final out = (n + l.langkah - 1) ~/ l.langkah;
    final padTotal = max((out - 1) * l.langkah + ke - n, 0);
    final padKiri = padTotal ~/ 2;
    final y = Float64List(out * l.keluar);
    for (var t = 0; t < out; t++) {
      final dasar = t * l.keluar;
      for (var o = 0; o < l.keluar; o++) {
        y[dasar + o] = l.b[o];
      }
      for (var j = 0; j < 5; j++) {
        final src = t * l.langkah + j * l.dilasi - padKiri;
        if (src < 0 || src >= n) continue;
        final xi = src * l.masuk;
        final kj = j * l.masuk * l.keluar;
        for (var i = 0; i < l.masuk; i++) {
          final v = x[xi + i];
          if (v == 0) continue;
          final ki = kj + i * l.keluar;
          for (var o = 0; o < l.keluar; o++) {
            y[dasar + o] += v * l.k[ki + o];
          }
        }
      }
      if (l.relu) {
        for (var o = 0; o < l.keluar; o++) {
          if (y[dasar + o] < 0) y[dasar + o] = 0;
        }
      }
    }
    return y;
  }

  /// Membersihkan satu jendela 768 sampel (1 lead, mV, 257 Hz).
  /// Lead tunggal disalin ke 12 kanal; keluaran 12 kanal dirata-rata.
  List<double> bersihkan(List<double> sinyal) {
    assert(sinyal.length == jendela);
    final abs = sinyal.map((v) => v.abs()).toList()..sort();
    final skala = abs[(0.995 * (abs.length - 1)).round()] + 1e-8;
    var n = jendela, kanal = lead;
    var x = Float64List(n * kanal);
    for (var t = 0; t < n; t++) {
      for (var c = 0; c < kanal; c++) {
        x[t * kanal + c] = sinyal[t] / skala;
      }
    }
    for (final l in _lapis) {
      if (l == null) {
        final y = Float64List(n * 2 * kanal);
        for (var t = 0; t < n; t++) {
          for (var c = 0; c < kanal; c++) {
            y[(2 * t) * kanal + c] = x[t * kanal + c];
            y[(2 * t + 1) * kanal + c] = x[t * kanal + c];
          }
        }
        x = y;
        n *= 2;
      } else {
        x = _conv(x, n, l);
        n = (n + l.langkah - 1) ~/ l.langkah;
        kanal = l.keluar;
      }
    }
    return [
      for (var t = 0; t < n; t++)
        () {
          var s = 0.0;
          for (var c = 0; c < kanal; c++) {
            s += x[t * kanal + c];
          }
          return s / kanal * skala;
        }()
    ];
  }
}

/// Model multitask (MTB-CDAE, TRAINING_MULTITASK_B_V4): encoder bersama, kepala klasifikasi
/// jenis noise (kelas 0 = BW, 1 = MA, 2 = EM), dan decoder yang dipandu peluang kelas.
/// Urutan bobot dan forward pass sama dengan tools/mtb_numpy.py:
///   conv1d..conv1d_3 (kernel, bias), batch_normalization (gamma, beta, mean, var),
///   dense (128x32, 32), dense_1 (32x3, 3), conv1d_4..conv1d_6 (kernel, bias).
/// Jumlah lead (1 atau 12) dibaca dari ukuran bobot: 87939 + 321 x lead.
class Mtb {
  static const kelas = ['BW', 'MA', 'EM'];
  final int lead;
  final List<_Lapis> _enc, _dec;
  final Float32List _gamma, _beta, _mu, _var, _d1k, _d1b, _d2k, _d2b;

  Mtb._(this.lead, this._enc, this._gamma, this._beta, this._mu, this._var, this._d1k, this._d1b, this._d2k, this._d2b,
      this._dec);

  factory Mtb.dariBytes(ByteData data) {
    final w = data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4);
    final sisa = w.length - 87939;
    if (sisa <= 0 || sisa % 321 != 0) throw StateError('ukuran bobot mtb tidak dikenal (${w.length})');
    final nl = sisa ~/ 321;
    var pos = 0;
    Float32List ambil(int n) {
      final v = Float32List.sublistView(w, pos, pos + n);
      pos += n;
      return v;
    }

    _Lapis lapis(int masuk, int keluar, int langkah, int dilasi, bool relu) =>
        _Lapis(ambil(5 * masuk * keluar), ambil(keluar), masuk, keluar, langkah, dilasi, relu);
    final enc = [lapis(nl, 32, 2, 1, true), lapis(32, 64, 2, 1, true), lapis(64, 64, 1, 1, true), lapis(64, 64, 1, 2, true)];
    final ga = ambil(128), be = ambil(128), mu = ambil(128), va = ambil(128);
    final d1k = ambil(128 * 32), d1b = ambil(32), d2k = ambil(32 * 3), d2b = ambil(3);
    final dec = [lapis(67, 64, 1, 1, true), lapis(64, 32, 1, 1, true), lapis(32, nl, 1, 1, false)];
    if (pos != w.length) throw StateError('ukuran bobot mtb tidak cocok ($pos vs ${w.length})');
    return Mtb._(nl, enc, ga, be, mu, va, d1k, d1b, d2k, d2b, dec);
  }

  /// Encoder + kepala klasifikasi. Mengembalikan (z, n, peluang [BW, MA, EM]).
  (Float64List, int, List<double>) _encode(List<double> sinyal, double skala) {
    var n = Cdae.jendela;
    var x = Float64List(n * lead);
    for (var t = 0; t < n; t++) {
      for (var c = 0; c < lead; c++) {
        x[t * lead + c] = sinyal[t] / skala;
      }
    }
    for (final l in _enc) {
      x = Cdae._conv(x, n, l);
      n = (n + l.langkah - 1) ~/ l.langkah;
    }
    // GlobalAveragePooling + GlobalMaxPooling -> BatchNorm -> Dense relu -> Dense softmax
    final c = Float64List(128);
    for (var o = 0; o < 64; o++) {
      var s = 0.0, m = double.negativeInfinity;
      for (var t = 0; t < n; t++) {
        final v = x[t * 64 + o];
        s += v;
        if (v > m) m = v;
      }
      c[o] = s / n;
      c[64 + o] = m;
    }
    for (var i = 0; i < 128; i++) {
      c[i] = (c[i] - _mu[i]) / sqrt(_var[i] + 1e-3) * _gamma[i] + _beta[i];
    }
    final h = List<double>.generate(32, (o) {
      var s = _d1b[o].toDouble();
      for (var i = 0; i < 128; i++) {
        s += c[i] * _d1k[i * 32 + o];
      }
      return max(0.0, s);
    });
    final lg = List<double>.generate(3, (o) {
      var s = _d2b[o].toDouble();
      for (var i = 0; i < 32; i++) {
        s += h[i] * _d2k[i * 3 + o];
      }
      return s;
    });
    final m = lg.reduce(max);
    final e = [for (final v in lg) exp(v - m)];
    final jml = e.reduce((a, b) => a + b);
    return (x, n, [for (final v in e) v / jml]);
  }

  static double _skala(List<double> sinyal) {
    final abs = sinyal.map((v) => v.abs()).toList()..sort();
    return abs[(0.995 * (abs.length - 1)).round()] + 1e-8;
  }

  /// Peluang jenis noise [BW, MA, EM] untuk satu jendela 768 sampel (1 lead, 257 Hz).
  List<double> klasifikasi(List<double> sinyal) {
    assert(sinyal.length == Cdae.jendela);
    return _encode(sinyal, _skala(sinyal)).$3;
  }

  /// Membersihkan satu jendela 768 sampel; mengembalikan (sinyal bersih, peluang jenis noise).
  (List<double>, List<double>) jalankan(List<double> sinyal) {
    assert(sinyal.length == Cdae.jendela);
    final skala = _skala(sinyal);
    final (z, n0, p) = _encode(sinyal, skala);
    var n = n0, kanal = 67;
    var x = Float64List(n * kanal);
    for (var t = 0; t < n; t++) {
      for (var c = 0; c < 64; c++) {
        x[t * kanal + c] = z[t * 64 + c];
      }
      for (var c = 0; c < 3; c++) {
        x[t * kanal + 64 + c] = p[c];
      }
    }
    for (final (i, l) in _dec.indexed) {
      if (i < 2) {
        final y = Float64List(n * 2 * kanal);
        for (var t = 0; t < n; t++) {
          for (var c = 0; c < kanal; c++) {
            y[(2 * t) * kanal + c] = x[t * kanal + c];
            y[(2 * t + 1) * kanal + c] = x[t * kanal + c];
          }
        }
        x = y;
        n *= 2;
      }
      x = Cdae._conv(x, n, l);
      kanal = l.keluar;
    }
    return (
      [
        for (var t = 0; t < n; t++)
          () {
            var s = 0.0;
            for (var c = 0; c < kanal; c++) {
              s += x[t * kanal + c];
            }
            return s / kanal * skala;
          }()
      ],
      p
    );
  }
}

/// Resample linear.
List<double> resample(List<double> x, double dari, double ke) {
  final n = (x.length * ke / dari).round();
  return [
    for (var i = 0; i < n; i++)
      () {
        final p = i * dari / ke;
        final a = p.floor().clamp(0, x.length - 1), b = min(a + 1, x.length - 1);
        final f = p - a;
        return x[a] * (1 - f) + x[b] * f;
      }()
  ];
}
