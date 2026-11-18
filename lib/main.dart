import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'ekg.dart';

// hanya putih dan hijau, ditambah abu untuk teks
const hijau = Color(0xFF1E6B45);
const hijauMuda = Color(0xFFEAF3EE);
const garis = Color(0xFFE3E8E5);
const tinta = Color(0xFF1C211E);
const redup = Color(0xFF6E7671);
const abuArtefak = Color(0xFFEDEFEE);

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Deteksi Artefak EKG',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: hijau, scaffoldBackgroundColor: Colors.white),
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
  String _nama = 'Rekaman contoh';
  String _info = '20 detik · 250 Hz';

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
        _nama = f.name;
        _info = '${(x.length / fs).toStringAsFixed(1)} detik · ${fs.round()} Hz';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
    }
  }

  Future<double?> _tanyaFs() {
    final c = TextEditingController(text: _fs.round().toString());
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Muat rekaman', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tinta)),
          const SizedBox(height: 4),
          const Text('CSV berisi 1 kolom amplitudo (mV), atau waktu,amplitudo.', style: TextStyle(color: redup, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Frekuensi sampling',
              suffixText: 'Hz',
              border: OutlineInputBorder(borderSide: BorderSide(color: garis)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: hijau, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))),
              child: const Text('Pilih file'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _h.stat;
    final durasi = _h.sinyal.length / _h.fs;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 20,
        title: const Text('Deteksi Artefak EKG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: tinta)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: garis)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nama, style: const TextStyle(fontWeight: FontWeight.w600, color: tinta)),
              Text(_info, style: const TextStyle(color: redup, fontSize: 12.5)),
            ]),
          ),
          TextButton(
            onPressed: () => setState(() {
              _h = analisis(sinyalContoh(), 250);
              _nama = 'Rekaman contoh';
              _info = '20 detik · 250 Hz';
            }),
            child: const Text('Contoh', style: TextStyle(color: hijau)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: hijau, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _muat,
            child: const Text('Muat CSV'),
          ),
        ]),
        const SizedBox(height: 16),
        AspectRatio(aspectRatio: 1.7, child: CustomPaint(painter: Grafik(_h))),
        const SizedBox(height: 8),
        const Text('Abu-abu: artefak, tidak dihitung.  ▼ hijau: detak normal.  ▼ hitam: PVC/PAC.',
            style: TextStyle(color: redup, fontSize: 11.5)),
        const SizedBox(height: 24),

        // angka utama
        Row(children: [
          _Angka('${s.hrRata.round()}', 'bpm rata-rata'),
          _Angka('${s.hrMax.round()}/${s.hrMin.round()}', 'bpm max/min'),
          _Angka('${s.totalBeat}', 'beat bersih'),
        ]),
        const SizedBox(height: 24),

        const _Judul('Detak jantung'),
        _Baris('Takikardia (> 100 bpm)', '${s.tachy} interval'),
        _Baris('Bradikardia (< 60 bpm)', '${s.brady} interval'),
        _Baris('Persentase taki / bradi', '${s.persenTachy.toStringAsFixed(1)}% / ${s.persenBrady.toStringAsFixed(1)}%'),
        _Baris('Interval R-R dipakai', '${s.jumlahInterval}'),
        const SizedBox(height: 24),

        const _Judul('Aritmia'),
        _Baris('PVC', '${_h.hitung('PVC')} beat'),
        _Baris('PAC', '${_h.hitung('PAC')} beat'),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Sementara memakai aturan klinis. Model AI menyusul.', style: TextStyle(color: redup, fontSize: 12)),
        ),
        const SizedBox(height: 24),

        _Judul('Segmen artefak', ekor: '${_h.artefak.length} segmen · ${durasi.toStringAsFixed(0)} detik rekaman'),
        if (_h.artefak.isEmpty) const _Baris('Tidak ada artefak', '-'),
        for (final (i, a) in _h.artefak.indexed)
          _Baris('${i + 1}.  ${a.mulai.toStringAsFixed(2)} s – ${a.selesai.toStringAsFixed(2)} s',
              '${(a.selesai - a.mulai).toStringAsFixed(2)} s'),
      ]),
    );
  }
}

class _Angka extends StatelessWidget {
  final String nilai, label;
  const _Angka(this.nilai, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nilai, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: hijau, height: 1.1)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: redup)),
        ]),
      );
}

class _Judul extends StatelessWidget {
  final String teks;
  final String? ekor;
  const _Judul(this.teks, {this.ekor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(teks, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tinta))),
          if (ekor != null) Text(ekor!, style: const TextStyle(fontSize: 12, color: redup)),
        ]),
      );
}

class _Baris extends StatelessWidget {
  final String k, v;
  const _Baris(this.k, this.v);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: garis))),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: tinta, fontSize: 14))),
          Text(v, style: const TextStyle(color: tinta, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );
}

class Grafik extends CustomPainter {
  final HasilAnalisis h;
  Grafik(this.h);

  @override
  void paint(Canvas c, Size size) {
    const kiri = 22.0, bawah = 18.0, atas = 4.0, kanan = 2.0;
    final w = size.width - kiri - kanan, ht = size.height - atas - bawah;
    final durasi = h.sinyal.length / h.fs;
    const lo = -4.0, hi = 4.0;
    double px(double t) => kiri + t / durasi * w;
    double py(double v) => atas + (hi - v.clamp(lo, hi)) / (hi - lo) * ht;

    for (final s in h.artefak) {
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht), Paint()..color = abuArtefak);
      if (px(s.selesai) - px(s.mulai) > 40) {
        _teks(c, 'ARTEFAK', Offset((px(s.mulai) + px(s.selesai)) / 2, atas + 4), 8.5, redup, bold: true, tengah: true);
      }
    }
    final tipis = Paint()
      ..color = garis
      ..strokeWidth = 1;
    final langkahGrid = durasi > 40 ? 10.0 : (durasi > 12 ? 2.0 : 1.0);
    for (var t = 0.0; t <= durasi + 1e-9; t += langkahGrid) {
      c.drawLine(Offset(px(t), atas), Offset(px(t), atas + ht), tipis);
    }
    c.drawLine(Offset(kiri, py(0)), Offset(kiri + w, py(0)), tipis);
    c.drawLine(Offset(kiri, atas + ht), Offset(kiri + w, atas + ht), Paint()..color = const Color(0xFFC9D0CC));

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
      ..color = tinta);

    for (final (k, i) in h.puncakR.indexed) {
      final j = h.jenisBeat[k];
      final warna = j == 'N' ? hijau : tinta;
      final x = px(i / h.fs), y = py(h.sinyal[i]) - 3;
      c.drawPath(Path()..moveTo(x - 4, y - 7)..lineTo(x + 4, y - 7)..lineTo(x, y)..close(), Paint()..color = warna);
      if (j != 'N') _teks(c, j, Offset(x, y - 19), 8, tinta, bold: true, tengah: true);
    }

    for (var t = 0.0; t <= durasi + 1e-9; t += langkahGrid) {
      if ((t / langkahGrid) % (w < 500 ? 2 : 1) == 0) {
        _teks(c, t.toStringAsFixed(0), Offset(px(t), atas + ht + 4), 9, redup, tengah: true);
      }
    }
    for (final v in [-2.0, 0.0, 2.0]) {
      _teks(c, v.toStringAsFixed(0), Offset(kiri - 14, py(v) - 6), 9, redup);
    }
  }

  void _teks(Canvas c, String s, Offset o, double ukuran, Color warna, {bool bold = false, bool tengah = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: ukuran, color: warna, fontWeight: bold ? FontWeight.w600 : null)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, tengah ? o.translate(-tp.width / 2, 0) : o);
  }

  @override
  bool shouldRepaint(covariant Grafik old) => old.h != h;
}
