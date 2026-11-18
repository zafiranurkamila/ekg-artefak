import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'ekg.dart';

void main() => runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, title: 'Deteksi Artefak EKG', home: Layar()));

class Layar extends StatefulWidget {
  const Layar({super.key});
  @override
  State<Layar> createState() => _LayarState();
}

class _LayarState extends State<Layar> {
  final _fs = TextEditingController(text: '250');
  late HasilAnalisis _h;
  String _info = 'Sinyal contoh (20 detik, 250 Hz)';

  @override
  void initState() {
    super.initState();
    _h = analisis(sinyalContoh(), 250);
  }

  Future<void> _muat() async {
    try {
      final fs = double.parse(_fs.text.replaceAll(',', '.'));
      final pilih = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['csv', 'txt'], withData: true);
      final f = pilih?.files.single;
      if (f == null || f.bytes == null) return;
      final x = bacaCsv(utf8.decode(f.bytes!, allowMalformed: true));
      if (x.length < fs * 2) throw 'data terlalu pendek';
      setState(() {
        _h = analisis(x, fs);
        _info = '${f.name} (${(x.length / fs).toStringAsFixed(1)} detik)';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _h.stat;
    final bersih = _h.sinyal.length / _h.fs - _h.artefak.fold(0.0, (a, g) => a + g.selesai - g.mulai);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
                width: 80,
                child: TextField(
                    controller: _fs,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true, labelText: 'fs (Hz)'))),
            FilledButton(onPressed: _muat, child: const Text('Muat CSV')),
            OutlinedButton(
                onPressed: () => setState(() {
                      _h = analisis(sinyalContoh(), 250);
                      _info = 'Sinyal contoh (20 detik, 250 Hz)';
                    }),
                child: const Text('Sinyal contoh')),
          ]),
          const SizedBox(height: 8),
          Text('$_info  |  artefak: ${_h.artefak.join(', ')}  |  bagian bersih ${bersih.toStringAsFixed(1)} s',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final sempit = box.maxWidth < 760;
              final grafik = CustomPaint(painter: Grafik(_h), size: Size.infinite);
              if (!sempit) {
                return Stack(children: [
                  Positioned.fill(child: grafik),
                  Positioned(left: 70, bottom: 40, child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '=== DASBOR HEART RATE ===\n'
                    'Total Beat          : ${s.totalBeat}\n'
                    'HR Max/Min          : ${s.hrMax.round()}/${s.hrMin.round()} bpm\n'
                    'Rata-rata HR        : ${s.hrRata.round()} bpm\n'
                    'Kejadian Tachycardia: ${s.tachy} interval\n'
                    'Kejadian Bradycardia: ${s.brady} interval\n'
                    'Takikardia/Bradikardia: ${s.persenTachy.toStringAsFixed(1)}% / ${s.persenBrady.toStringAsFixed(1)}%\n'
                    'Interval dipakai    : ${s.jumlahInterval} (artefak dibuang)',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                )),
                ]);
              }
              return Column(children: [
                Expanded(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: 1100, height: box.maxHeight, child: grafik))),
                const SizedBox(height: 8),
                const Text('Geser grafik ke kiri/kanan', style: TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '=== DASBOR HEART RATE ===\n'
                    'Total Beat          : ${s.totalBeat}\n'
                    'HR Max/Min          : ${s.hrMax.round()}/${s.hrMin.round()} bpm\n'
                    'Rata-rata HR        : ${s.hrRata.round()} bpm\n'
                    'Kejadian Tachycardia: ${s.tachy} interval\n'
                    'Kejadian Bradycardia: ${s.brady} interval\n'
                    'Takikardia/Bradikardia: ${s.persenTachy.toStringAsFixed(1)}% / ${s.persenBrady.toStringAsFixed(1)}%\n'
                    'Interval dipakai    : ${s.jumlahInterval} (artefak dibuang)',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ]);
            }),
          ),
        ]),
      )),
    );
  }
}

class Grafik extends CustomPainter {
  final HasilAnalisis h;
  Grafik(this.h);

  @override
  void paint(Canvas c, Size size) {
    const kiri = 60.0, bawah = 30.0, atas = 10.0, kanan = 10.0;
    final w = size.width - kiri - kanan, ht = size.height - atas - bawah;
    final durasi = h.sinyal.length / h.fs;
    var lo = h.sinyal.reduce((a, b) => a < b ? a : b), hi = h.sinyal.reduce((a, b) => a > b ? a : b);
    lo = lo.clamp(-5, -1).toDouble();
    hi = hi.clamp(1, 5).toDouble();
    double px(double t) => kiri + t / durasi * w;
    double py(double v) => atas + (hi - v) / (hi - lo) * ht;

    // latar bersih (hijau) dan artefak (merah) per blok 2 detik
    c.drawRect(Rect.fromLTWH(kiri, atas, w, ht), Paint()..color = const Color(0xFFE8F4E8));
    final merah = Paint()..color = const Color(0xFFF2BDBD);
    for (final s in h.artefak) {
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht), merah);
      for (var t = s.mulai; t < s.selesai - 1e-9; t += 2) {
        _teks(c, 'ARTEFAK', Offset(px(t + 1), atas + 30), 10, const Color(0xFFC62828), bold: true, tengah: true, latar: true);
      }
    }
    // grid tiap 2 detik dan sumbu
    final garis = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    for (var t = 0.0; t <= durasi + 1e-9; t += 2) {
      for (var y = atas; y < atas + ht; y += 8) {
        c.drawLine(Offset(px(t), y), Offset(px(t), y + 4), garis);
      }
      _teks(c, t.toStringAsFixed(1), Offset(px(t), atas + ht + 6), 11, Colors.black87, tengah: true);
    }
    for (var v = lo.ceilToDouble(); v <= hi; v += 2) {
      _teks(c, v.toStringAsFixed(0), Offset(kiri - 22, py(v) - 7), 11, Colors.black87);
    }
    _teks(c, 'Waktu (detik)', Offset(kiri + w / 2, atas + ht + 18), 11, Colors.black87, tengah: true);
    c.drawRect(Rect.fromLTWH(kiri, atas, w, ht),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54);

    // sinyal
    final p = Path();
    final langkah = (h.sinyal.length / (w * 2)).ceil().clamp(1, 1000);
    for (var i = 0; i < h.sinyal.length; i += langkah) {
      final o = Offset(px(i / h.fs), py(h.sinyal[i].clamp(lo, hi)));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black);

    // puncak R
    final biru = Paint()..color = const Color(0xFF1F77B4);
    for (final i in h.puncakR) {
      final x = px(i / h.fs), y = py(h.sinyal[i]) - 6;
      c.drawPath(
          Path()
            ..moveTo(x - 6, y - 10)
            ..lineTo(x + 6, y - 10)
            ..lineTo(x, y)
            ..close(),
          biru);
    }
    _teks(c, '— Sinyal EKG    ▼ Puncak R (Pan-Tompkins, hanya di bagian bersih)',
        Offset(kiri + w - 8, atas + 6), 11, Colors.black87, kananRata: true, latar: true);
  }

  void _teks(Canvas c, String s, Offset o, double ukuran, Color warna,
      {bool bold = false, bool tengah = false, bool kananRata = false, bool latar = false}) {
    final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(fontSize: ukuran, color: warna, fontWeight: bold ? FontWeight.bold : null)),
        textDirection: TextDirection.ltr)
      ..layout();
    var pos = o;
    if (tengah) pos = o.translate(-tp.width / 2, 0);
    if (kananRata) pos = o.translate(-tp.width, 0);
    if (latar) {
      c.drawRect(Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4), Paint()..color = Colors.white);
    }
    tp.paint(c, pos);
  }

  @override
  bool shouldRepaint(covariant Grafik old) => old.h != h;
}
