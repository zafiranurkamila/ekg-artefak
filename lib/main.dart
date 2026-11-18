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
          AspectRatio(aspectRatio: 1.45, child: CustomPaint(painter: Grafik(_h))),
          const SizedBox(height: 8),
          const Wrap(alignment: WrapAlignment.center, runSpacing: 4, children: [
            _Titik(warna: Color(0xFFF2BDBD), teks: 'Artefak'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFFCFE6CF), teks: 'Bersih'),
            SizedBox(width: 14),
            _Titik(warna: Color(0xFF1F77B4), teks: 'Puncak R'),
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

  // warna mengikuti grafik referensi dari Bapak
  static const merahArea = Color(0xFFF2BDBD), hijauArea = Color(0xFFE8F4E8);
  static const merahTeks = Color(0xFFC62828), biruR = Color(0xFF1F77B4);

  @override
  void paint(Canvas c, Size size) {
    const kiri = 34.0, bawah = 30.0, atas = 4.0, kanan = 4.0;
    final w = size.width - kiri - kanan, ht = size.height - atas - bawah;
    final durasi = h.sinyal.length / h.fs;
    const lo = -5.0, hi = 5.0;
    double px(double t) => kiri + t / durasi * w;
    double py(double v) => atas + (hi - v.clamp(lo, hi)) / (hi - lo) * ht;
    final kecil = w < 500;

    // latar: bersih hijau, artefak merah
    c.drawRect(Rect.fromLTWH(kiri, atas, w, ht), Paint()..color = hijauArea);
    for (final s in h.artefak) {
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht), Paint()..color = merahArea);
    }
    // garis putus-putus tiap 2 detik (seperti referensi)
    final putus = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 0.8;
    final blok = durasi > 40 ? 10.0 : 2.0;
    for (var t = blok; t < durasi; t += blok) {
      for (var y = atas; y < atas + ht; y += 7) {
        c.drawLine(Offset(px(t), y), Offset(px(t), y + 4), putus);
      }
    }
    // label ARTEFAK di kotak putih
    for (final s in h.artefak) {
      if (px(s.selesai) - px(s.mulai) > 34) {
        _label(c, 'ARTEFAK', Offset((px(s.mulai) + px(s.selesai)) / 2, atas + ht * 0.1), kecil ? 6.5 : 9);
      }
    }

    // sinyal EKG, garis hitam tipis
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
      ..strokeWidth = 0.8
      ..color = Colors.black);

    // puncak R: segitiga biru; PVC/PAC diberi label
    final ukuran = kecil ? 3.5 : 5.0;
    for (final (k, i) in h.puncakR.indexed) {
      final j = h.jenisBeat[k];
      final x = px(i / h.fs), y = py(h.sinyal[i]) - 2;
      c.drawPath(
          Path()
            ..moveTo(x - ukuran, y - ukuran * 1.8)
            ..lineTo(x + ukuran, y - ukuran * 1.8)
            ..lineTo(x, y)
            ..close(),
          Paint()..color = biruR);
      if (j != 'N') _teks(c, j, Offset(x, y - ukuran * 1.8 - 11), kecil ? 7 : 9, Colors.black, bold: true, tengah: true);
    }

    // bingkai dan sumbu
    c.drawRect(Rect.fromLTWH(kiri, atas, w, ht), Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black
      ..strokeWidth = 0.8);
    final fs = kecil ? 7.5 : 10.0;
    final langkahX = durasi > 40 ? 10.0 : (durasi > 12 ? 2.5 : 1.0);
    for (var t = 0.0; t <= durasi + 1e-9; t += langkahX) {
      c.drawLine(Offset(px(t), atas + ht), Offset(px(t), atas + ht + 3), Paint()..color = Colors.black);
      if (!kecil || (t / langkahX) % 2 == 0) {
        _teks(c, t.toStringAsFixed(1), Offset(px(t), atas + ht + 4), fs, Colors.black, tengah: true);
      }
    }
    for (final v in [-4.0, -2.0, 0.0, 2.0, 4.0]) {
      c.drawLine(Offset(kiri - 3, py(v)), Offset(kiri, py(v)), Paint()..color = Colors.black);
      _teks(c, v.toStringAsFixed(0), Offset(kiri - 13, py(v) - fs * 0.65), fs, Colors.black);
    }
    _teks(c, 'Waktu (Detik)', Offset(kiri + w / 2, atas + ht + 4 + fs + 3), fs, Colors.black, tengah: true);
    c.save();
    c.translate(2, atas + ht / 2);
    c.rotate(-1.5708);
    _teks(c, 'Amplitudo (mV)', Offset(0, -1), fs, Colors.black, tengah: true);
    c.restore();

    // legenda kanan atas
    final lg = TextStyle(fontSize: kecil ? 7 : 10, color: Colors.black);
    final t1 = TextPainter(text: TextSpan(text: 'Sinyal Dinamis EKG (+ PVC/PAC)', style: lg), textDirection: TextDirection.ltr)..layout();
    final t2 = TextPainter(text: TextSpan(text: 'Puncak R (Pan-Tompkins)', style: lg), textDirection: TextDirection.ltr)..layout();
    final simbol = kecil ? 16.0 : 24.0;
    final lebar = simbol + 6 + (t1.width > t2.width ? t1.width : t2.width) + 10;
    final tinggi = t1.height + t2.height + 10;
    final kotak = Rect.fromLTWH(kiri + w - lebar - 4, atas + 4, lebar, tinggi);
    c.drawRRect(RRect.fromRectAndRadius(kotak, const Radius.circular(3)), Paint()..color = const Color(0xEEFFFFFF));
    c.drawRRect(RRect.fromRectAndRadius(kotak, const Radius.circular(3)), Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x33000000));
    final y1 = kotak.top + 5 + t1.height / 2, y2 = kotak.top + 5 + t1.height + t2.height / 2;
    c.drawLine(Offset(kotak.left + 5, y1), Offset(kotak.left + 5 + simbol, y1), Paint()..color = Colors.black);
    final cx = kotak.left + 5 + simbol / 2, u = kecil ? 3.0 : 4.5;
    c.drawPath(Path()..moveTo(cx - u, y2 - u)..lineTo(cx + u, y2 - u)..lineTo(cx, y2 + u)..close(), Paint()..color = biruR);
    t1.paint(c, Offset(kotak.left + 11 + simbol, kotak.top + 5));
    t2.paint(c, Offset(kotak.left + 11 + simbol, kotak.top + 5 + t1.height));
  }

  void _label(Canvas c, String s, Offset tengah, double ukuran) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: ukuran, color: merahTeks, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr)
      ..layout();
    final r = Rect.fromCenter(center: tengah, width: tp.width + 8, height: tp.height + 4);
    c.drawRect(r, Paint()..color = Colors.white);
    tp.paint(c, Offset(r.left + 4, r.top + 2));
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
