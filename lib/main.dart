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
    final durasi = _h.sinyal.length / _h.fs;
    final durArt = _h.artefak.fold(0.0, (a, g) => a + g.selesai - g.mulai);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: hijau,
        foregroundColor: Colors.white,
        title: const Text('Deteksi Artefak EKG', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              tooltip: 'Sinyal contoh',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                    _h = analisis(sinyalContoh(), 250);
                    _sumber = 'Sinyal contoh · 20 detik · 250 Hz';
                  })),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _muat, backgroundColor: hijau, foregroundColor: Colors.white,
          icon: const Icon(Icons.upload_file), label: const Text('Muat CSV')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Text(_sumber, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
        const SizedBox(height: 8),
        _Kartu(
          judul: 'Sinyal EKG',
          isi: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Wrap(spacing: 14, runSpacing: 4, children: [
              _Legenda(warna: Color(0xFFF2BDBD), teks: 'Artefak (dibuang)'),
              _Legenda(warna: Color(0xFFDFF0E3), teks: 'Bersih'),
              _Legenda(warna: Color(0xFF1F77B4), teks: 'Puncak R', segitiga: true),
            ]),
            const SizedBox(height: 8),
            AspectRatio(aspectRatio: 1.9, child: CustomPaint(painter: Grafik(_h))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _Angka('${s.hrRata.round()}', 'Rata-rata HR', 'bpm')),
          const SizedBox(width: 8),
          Expanded(child: _Angka('${s.hrMax.round()}/${s.hrMin.round()}', 'HR max/min', 'bpm')),
          const SizedBox(width: 8),
          Expanded(child: _Angka('${s.totalBeat}', 'Total beat', 'bersih')),
        ]),
        const SizedBox(height: 10),
        _Kartu(
          judul: 'Segmen Artefak',
          ekor: Text('${_h.artefak.length} segmen · ${durArt.toStringAsFixed(1)} dari ${durasi.toStringAsFixed(0)} s',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          isi: _h.artefak.isEmpty
              ? const Text('Tidak ada artefak terdeteksi.')
              : Column(children: [
                  for (final (i, a) in _h.artefak.indexed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(radius: 14, backgroundColor: const Color(0xFFF8D7D7),
                          child: Text('${i + 1}', style: const TextStyle(color: merah, fontWeight: FontWeight.bold, fontSize: 12))),
                      title: Text('Mulai ${a.mulai.toStringAsFixed(2)} s  →  selesai ${a.selesai.toStringAsFixed(2)} s',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Durasi ${(a.selesai - a.mulai).toStringAsFixed(2)} s · tidak masuk perhitungan HR'),
                    ),
                ]),
        ),
        const SizedBox(height: 10),
        _Kartu(
          judul: 'Dasbor Heart Rate',
          isi: Column(children: [
            _Baris('Total beat (bagian bersih)', '${s.totalBeat}'),
            _Baris('HR max / min', '${s.hrMax.round()} / ${s.hrMin.round()} bpm'),
            _Baris('Rata-rata HR', '${s.hrRata.round()} bpm'),
            _Baris('Kejadian takikardia (>100 bpm)', '${s.tachy} interval'),
            _Baris('Kejadian bradikardia (<60 bpm)', '${s.brady} interval'),
            _Baris('Takikardia / bradikardia', '${s.persenTachy.toStringAsFixed(1)}% / ${s.persenBrady.toStringAsFixed(1)}%'),
            _Baris('Interval R-R dipakai', '${s.jumlahInterval}'),
          ]),
        ),
        const SizedBox(height: 10),
        const _Kartu(
          judul: 'Model AI (tahap berikutnya)',
          isi: Text('Segmen artefak nantinya dibersihkan dengan model denoising (CDAE/LSTM-AE/Attention-AE) '
              'sebelum dihitung ulang. Saat ini segmen artefak dibuang dari perhitungan.',
              style: TextStyle(fontSize: 13, color: Colors.black87)),
        ),
      ]),
    );
  }
}

class _Kartu extends StatelessWidget {
  final String judul;
  final Widget isi;
  final Widget? ekor;
  const _Kartu({required this.judul, required this.isi, this.ekor});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(judul, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: hijau))),
              if (ekor != null) ekor!,
            ]),
            const SizedBox(height: 10),
            isi,
          ]),
        ),
      );
}

class _Angka extends StatelessWidget {
  final String nilai, label, satuan;
  const _Angka(this.nilai, this.label, this.satuan);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nilai, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: hijau)),
          Text(satuan, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Baris extends StatelessWidget {
  final String k, v;
  const _Baris(this.k, this.v);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black87))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Legenda extends StatelessWidget {
  final Color warna;
  final String teks;
  final bool segitiga;
  const _Legenda({required this.warna, required this.teks, this.segitiga = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        segitiga
            ? Icon(Icons.arrow_drop_down, color: warna, size: 22)
            : Container(width: 14, height: 10, decoration: BoxDecoration(color: warna, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(teks, style: const TextStyle(fontSize: 12)),
      ]);
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
