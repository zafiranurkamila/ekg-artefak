import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'ekg.dart';

// palet mengikuti contoh: krem, hijau zaitun, aksen oranye
const krem = Color(0xFFFFFFFF); // latar putih
const zaitun = Color(0xFF1E6B45);
const zaitunTua = Color(0xFF14532F);
const zaitunMuda = Color(0xFFEAF3EE);
const oranye = Color(0xFF1E6B45);
const merahLembut = Color(0xFFEAF3EE);
const tinta = Color(0xFF2B2B22);
const redup = Color(0xFF7A7A6E);
const warnaBeat = {'N': Color(0xFF1E6B45), 'PVC': Color(0xFF1C211E), 'PAC': Color(0xFF1C211E)};

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Deteksi Artefak EKG',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: zaitun, scaffoldBackgroundColor: krem),
      home: const Layar(),
    ));

BoxDecoration kartu([Color warna = Colors.white]) => BoxDecoration(
      color: warna,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4))],
    );

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

  void _contoh() => setState(() {
        _h = analisis(sinyalContoh(), 250);
        _nama = 'Rekaman contoh';
        _info = '20 detik · 250 Hz';
      });

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
      backgroundColor: krem,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Muat Rekaman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tinta)),
          const SizedBox(height: 4),
          const Text('File CSV berisi 1 kolom amplitudo (mV), atau waktu,amplitudo.',
              style: TextStyle(color: redup, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: kartu(),
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: InputBorder.none, labelText: 'Frekuensi sampling', suffixText: 'Hz'),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: _TombolPil(
                teks: 'Pilih File CSV',
                ikon: Icons.upload_file_rounded,
                onTap: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.')))),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: _beranda()),
      );

  Widget _judul(String t, [Widget? ekor]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tinta))),
          if (ekor != null) ekor,
        ]),
      );

  Widget _beranda() {
    final s = _h.stat;
    final durasi = _h.sinyal.length / _h.fs;
    final durArt = _h.artefak.fold(0.0, (a, g) => a + g.selesai - g.mulai);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 24), children: [
      Row(children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Halo, Dok', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tinta)),
            SizedBox(height: 2),
            Text('Cek kualitas rekaman EKG hari ini', style: TextStyle(color: redup, fontSize: 13)),
          ]),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: kartu(zaitunMuda),
          child: const Icon(Icons.monitor_heart_rounded, color: zaitun),
        ),
      ]),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: kartu(zaitunMuda),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nama, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: zaitunTua)),
              const SizedBox(height: 2),
              Text(_info, style: const TextStyle(color: zaitunTua, fontSize: 13)),
              const SizedBox(height: 12),
              _TombolPil(teks: 'Ganti rekaman', ikon: Icons.swap_horiz_rounded, kecil: true, onTap: _muat),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            width: 74,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text('${_h.artefak.length}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: oranye)),
              const Text('artefak', style: TextStyle(fontSize: 11, color: redup)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      _judul('Sinyal EKG', TextButton(onPressed: _contoh, child: const Text('Pakai contoh', style: TextStyle(color: oranye)))),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: kartu(),
        child: Column(children: [
          AspectRatio(aspectRatio: 1.75, child: CustomPaint(painter: Grafik(_h))),
          const SizedBox(height: 8),
          const Wrap(alignment: WrapAlignment.center, runSpacing: 4, children: [
            _Titik(warna: Color(0xFFD5DAD7), teks: 'Artefak'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFFD6EADD), teks: 'Bersih'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFF1E6B45), teks: 'Normal'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFF1C211E), teks: 'PVC'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFF1C211E), teks: 'PAC'),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      _judul('Detak Jantung'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: kartu(),
        child: Column(children: [
          Row(children: [
            Expanded(child: _Detail(ikon: Icons.favorite_rounded, label: 'Rata-rata', nilai: '${s.hrRata.round()} bpm')),
            Expanded(child: _Detail(ikon: Icons.swap_vert_rounded, label: 'Max / Min', nilai: '${s.hrMax.round()} / ${s.hrMin.round()}')),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Detail(ikon: Icons.speed_rounded, label: 'Takikardia', nilai: '${s.tachy} interval')),
            Expanded(child: _Detail(ikon: Icons.hourglass_bottom_rounded, label: 'Bradikardia', nilai: '${s.brady} interval')),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Detail(ikon: Icons.graphic_eq_rounded, label: 'Total beat', nilai: '${s.totalBeat} beat')),
            Expanded(
                child: _Detail(
                    ikon: Icons.pie_chart_rounded,
                    label: 'Taki / Bradi',
                    nilai: '${s.persenTachy.toStringAsFixed(0)}% / ${s.persenBrady.toStringAsFixed(0)}%')),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      _judul('Aritmia', const Text('aturan klinis · model AI menyusul', style: TextStyle(color: redup, fontSize: 12))),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: kartu(),
        child: Row(children: [
          Expanded(child: _Detail(ikon: Icons.bolt_rounded, label: 'PVC', nilai: '${_h.hitung('PVC')} beat')),
          Expanded(child: _Detail(ikon: Icons.timelapse_rounded, label: 'PAC', nilai: '${_h.hitung('PAC')} beat')),
        ]),
      ),
      const SizedBox(height: 18),
      _judul('Segmen Artefak',
          Text('${durArt.toStringAsFixed(1)} dari ${durasi.toStringAsFixed(0)} detik', style: const TextStyle(color: redup, fontSize: 12.5))),
      if (_h.artefak.isEmpty)
        Container(
            padding: const EdgeInsets.all(16),
            decoration: kartu(),
            child: const Text('Tidak ada artefak. Semua sinyal dihitung.', style: TextStyle(color: zaitunTua))),
      for (final (i, a) in _h.artefak.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: kartu(),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: merahLembut, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14532F), fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a.mulai.toStringAsFixed(2)} s  –  ${a.selesai.toStringAsFixed(2)} s',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: tinta)),
                const SizedBox(height: 2),
                const Text('Tidak masuk perhitungan HR', style: TextStyle(color: redup, fontSize: 12.5)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: zaitunMuda, borderRadius: BorderRadius.circular(20)),
              child: Text('${(a.selesai - a.mulai).toStringAsFixed(1)} s',
                  style: const TextStyle(color: zaitunTua, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
          ]),
        ),
    ]);
  }
}

class _TombolPil extends StatelessWidget {
  final String teks;
  final IconData ikon;
  final VoidCallback onTap;
  final bool kecil;
  const _TombolPil({required this.teks, required this.ikon, required this.onTap, this.kecil = false});
  @override
  Widget build(BuildContext context) => Material(
        color: zaitunTua,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: kecil ? 14 : 20, vertical: kecil ? 9 : 15),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ikon, color: Colors.white, size: kecil ? 17 : 20),
              const SizedBox(width: 8),
              Text(teks, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: kecil ? 13 : 15)),
            ]),
          ),
        ),
      );
}

class _Detail extends StatelessWidget {
  final IconData ikon;
  final String label, nilai;
  const _Detail({required this.ikon, required this.label, required this.nilai});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: zaitunMuda, borderRadius: BorderRadius.circular(13)),
          child: Icon(ikon, color: zaitun, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: redup, fontSize: 12)),
            Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700, color: tinta, fontSize: 14.5)),
          ]),
        ),
      ]);
}

class _Titik extends StatelessWidget {
  final Color warna;
  final String teks;
  const _Titik({required this.warna, required this.teks});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: warna, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(teks, style: const TextStyle(fontSize: 12, color: redup)),
      ]);
}

class Grafik extends CustomPainter {
  final HasilAnalisis h;
  Grafik(this.h);

  @override
  void paint(Canvas c, Size size) {
    const kiri = 22.0, bawah = 18.0, atas = 4.0, kanan = 4.0;
    final w = size.width - kiri - kanan, ht = size.height - atas - bawah;
    final durasi = h.sinyal.length / h.fs;
    const lo = -4.0, hi = 4.0;
    double px(double t) => kiri + t / durasi * w;
    double py(double v) => atas + (hi - v.clamp(lo, hi)) / (hi - lo) * ht;
    final area = RRect.fromRectAndRadius(Rect.fromLTWH(kiri, atas, w, ht), const Radius.circular(12));

    c.save();
    c.clipRRect(area);
    c.drawRect(area.outerRect, Paint()..color = const Color(0xFFF5F9F6));
    for (final s in h.artefak) {
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht), Paint()..color = const Color(0xFFE6E9E7));
      if (px(s.selesai) - px(s.mulai) > 40) {
        _teks(c, 'ARTEFAK', Offset((px(s.mulai) + px(s.selesai)) / 2, atas + 5), 8.5, const Color(0xFF14532F),
            bold: true, tengah: true);
      }
    }
    final garis = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 0.8;
    final langkahGrid = durasi > 40 ? 10.0 : (durasi > 12 ? 2.0 : 1.0);
    for (var t = langkahGrid; t < durasi; t += langkahGrid) {
      for (var y = atas; y < atas + ht; y += 6) {
        c.drawLine(Offset(px(t), y), Offset(px(t), y + 3), garis);
      }
    }
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
      final x = px(i / h.fs), y = py(h.sinyal[i]) - 3;
      c.drawPath(Path()..moveTo(x - 4, y - 7)..lineTo(x + 4, y - 7)..lineTo(x, y)..close(),
          Paint()..color = warnaBeat[j]!);
      if (j != 'N') _teks(c, j, Offset(x, y - 19), 8, warnaBeat[j]!, bold: true, tengah: true);
    }
    c.restore();
    for (var t = 0.0; t <= durasi + 1e-9; t += langkahGrid) {
      if ((t / langkahGrid) % (w < 500 ? 2 : 1) == 0) {
        _teks(c, t.toStringAsFixed(0), Offset(px(t), atas + ht + 4), 9, redup, tengah: true);
      }
    }
    for (final v in [-2.0, 0.0, 2.0]) {
      _teks(c, v.toStringAsFixed(0), Offset(kiri - 13, py(v) - 6), 9, redup);
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
