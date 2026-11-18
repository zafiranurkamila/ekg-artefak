import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'ekg.dart';

const hijau = Color(0xFF14724A);
const merah = Color(0xFFC62828);

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Deteksi Artefak EKG',
      theme: ThemeData(colorSchemeSeed: hijau, useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF4F7F5)),
      home: const Layar(),
    ));

class Layar extends StatefulWidget {
  const Layar({super.key});
  @override
  State<Layar> createState() => _LayarState();
}

class _LayarState extends State<Layar> {
  double _fs = 250;
  late HasilAnalisis _h;
  String _sumber = 'Sinyal contoh · 20 detik · 250 Hz';

  @override
  void initState() {
    super.initState();
    _h = analisis(sinyalContoh(), 250);
  }

  Future<void> _muat() async {
    final fs = await _tanyaFs();
    if (fs == null) return;
    try {
      final pilih = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt'], withData: true);
      final f = pilih?.files.single;
      if (f == null || f.bytes == null) return;
      final x = bacaCsv(utf8.decode(f.bytes!, allowMalformed: true));
      if (x.length < fs * 2) throw 'data terlalu pendek';
      setState(() {
        _fs = fs;
        _h = analisis(x, fs);
        _sumber = '${f.name} · ${(x.length / fs).toStringAsFixed(1)} detik · ${fs.round()} Hz';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
    }
  }

  Future<double?> _tanyaFs() {
    final c = TextEditingController(text: _fs.round().toString());
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frekuensi sampling'),
        content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(suffixText: 'Hz', helperText: 'File CSV: 1 kolom amplitudo (mV), atau waktu,amplitudo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))), child: const Text('Pilih file')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _h.stat;
    const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier New', 'Courier'], fontSize: 12.5, height: 1.45);
    String r(String k, String v) => '${k.padRight(24)}: $v';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text('Deteksi Artefak EKG', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: Text(_sumber, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          TextButton(
              onPressed: () => setState(() {
                    _h = analisis(sinyalContoh(), 250);
                    _sumber = 'Sinyal contoh · 20 detik · 250 Hz';
                  }),
              child: const Text('Contoh')),
          OutlinedButton(onPressed: _muat, child: const Text('Muat CSV')),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
          child: AspectRatio(aspectRatio: 1.7, child: CustomPaint(painter: Grafik(_h))),
        ),
        const SizedBox(height: 4),
        const Text('Merah: artefak (tidak dihitung)   Hijau: sinyal bersih   ▼ puncak R (Pan-Tompkins)',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE08080)), borderRadius: BorderRadius.circular(6)),
          child: Text(
            [
              '=== DASBOR HEART RATE ===',
              r('Total Beat', '${s.totalBeat}'),
              r('HR Max/Min', '${s.hrMax.round()}/${s.hrMin.round()} bpm'),
              r('Rata-rata HR', '${s.hrRata.round()} bpm'),
              r('Kejadian Tachycardia', '${s.tachy} interval'),
              r('Kejadian Bradycardia', '${s.brady} interval'),
              r('Takikardia/Bradikardia', '${s.persenTachy.toStringAsFixed(1)}% / ${s.persenBrady.toStringAsFixed(1)}%'),
              '',
              '=== SEGMEN ARTEFAK ===',
              if (_h.artefak.isEmpty) 'Tidak ada',
              for (final (i, a) in _h.artefak.indexed)
                '${i + 1}. ${a.mulai.toStringAsFixed(2)} s - ${a.selesai.toStringAsFixed(2)} s (${(a.selesai - a.mulai).toStringAsFixed(2)} s)',
            ].join('\n'),
            style: mono,
          ),
        ),
      ]),
    );
  }
}

class Grafik extends CustomPainter {
  final HasilAnalisis h;
  Grafik(this.h);

  @override
  void paint(Canvas c, Size size) {
    const kiri = 26.0, bawah = 18.0, atas = 4.0, kanan = 4.0;
    final w = size.width - kiri - kanan, ht = size.height - atas - bawah;
    final durasi = h.sinyal.length / h.fs;
    const lo = -4.0, hi = 4.0;
    double px(double t) => kiri + t / durasi * w;
    double py(double v) => atas + (hi - v.clamp(lo, hi)) / (hi - lo) * ht;

    c.drawRect(Rect.fromLTWH(kiri, atas, w, ht), Paint()..color = const Color(0xFFDFF0E3));
    for (final s in h.artefak) {
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht), Paint()..color = const Color(0xFFF2BDBD));
      if (px(s.selesai) - px(s.mulai) > 40) {
        _teks(c, 'ARTEFAK', Offset((px(s.mulai) + px(s.selesai)) / 2, atas + 4), 9, merah, bold: true, tengah: true);
      }
    }
    final garis = Paint()
      ..color = Colors.black26
      ..strokeWidth = 0.8;
    final langkahGrid = durasi > 40 ? 10.0 : (durasi > 12 ? 2.0 : 1.0);
    for (var t = 0.0; t <= durasi + 1e-9; t += langkahGrid) {
      for (var y = atas; y < atas + ht; y += 6) {
        c.drawLine(Offset(px(t), y), Offset(px(t), y + 3), garis);
      }
      if ((t / langkahGrid) % (w < 500 ? 2 : 1) == 0) {
        _teks(c, t.toStringAsFixed(0), Offset(px(t), atas + ht + 3), 9, Colors.black54, tengah: true);
      }
    }
    for (final v in [-2.0, 0.0, 2.0]) {
      _teks(c, v.toStringAsFixed(0), Offset(kiri - 14, py(v) - 6), 9, Colors.black54);
    }

    // sinyal: ambil min/max tiap piksel agar noise tetap terlihat walau grafik kecil
    final p = Path();
    final perPx = h.sinyal.length / w;
    for (var k = 0; k < w; k++) {
      final a = (k * perPx).floor(), z = ((k + 1) * perPx).ceil().clamp(a + 1, h.sinyal.length);
      var mn = h.sinyal[a], mx = h.sinyal[a];
      for (var i = a; i < z; i++) {
        if (h.sinyal[i] < mn) mn = h.sinyal[i];
        if (h.sinyal[i] > mx) mx = h.sinyal[i];
      }
      final x = kiri + k.toDouble();
      if (k == 0) p.moveTo(x, py(mx));
      p.lineTo(x, py(mx));
      p.lineTo(x, py(mn));
    }
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.black87);

    final biru = Paint()..color = const Color(0xFF1F77B4);
    for (final i in h.puncakR) {
      final x = px(i / h.fs), y = py(h.sinyal[i]) - 3;
      c.drawPath(Path()..moveTo(x - 4, y - 7)..lineTo(x + 4, y - 7)..lineTo(x, y)..close(), biru);
    }
  }

  void _teks(Canvas c, String s, Offset o, double ukuran, Color warna, {bool bold = false, bool tengah = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: ukuran, color: warna, fontWeight: bold ? FontWeight.bold : null)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, tengah ? o.translate(-tp.width / 2, 0) : o);
  }

  @override
  bool shouldRepaint(covariant Grafik old) => old.h != h;
}
