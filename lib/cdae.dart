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
  static const fs = 257.0, jendela = 768, lead = 12;
  final List<_Lapis?> _lapis; // null = UpSampling x2

  Cdae._(this._lapis);

  factory Cdae.dariBytes(ByteData data) {
    final w = data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4);
    var pos = 0;
    const spek = [
      [12, 32, 2, 1, 1], [32, 64, 2, 1, 1], [64, 64, 1, 1, 1], [64, 64, 1, 2, 1], null,
      [64, 64, 1, 1, 1], null, [64, 32, 1, 1, 1], [32, 12, 1, 1, 0],
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
    return Cdae._(lapis);
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
