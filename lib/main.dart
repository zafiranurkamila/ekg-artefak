import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cdae.dart';
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
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2))],
    );

class Layar extends StatefulWidget {
  const Layar({super.key});
  @override
  State<Layar> createState() => _LayarState();
}

class _LayarState extends State<Layar> {
  double _fs = 250;
  List<double> _x = sinyalContoh();
  late HasilAnalisis _h;
  String _nama = 'Rekaman contoh';
  String _info = '20 detik · 250 Hz';
  final Map<String, Cdae> _model = {};
  bool _pakaiModel = false;

  @override
  void initState() {
    super.initState();
    _h = analisis(_x, _fs);
    _muatModel();
  }

  Future<void> _muatModel() async {
    for (final j in ['bw', 'ma', 'em']) {
      try {
        _model[j] = Cdae.dariBytes(await rootBundle.load('assets/model/$j.bin'));
      } catch (_) {} // model yang belum ada dilewati
    }
    if (mounted) setState(() {});
  }

  void _hitung() => _h = _pakaiModel && _model.isNotEmpty ? analisisDenganModel(_x, _fs, _model) : analisis(_x, _fs);

  void _contoh() => setState(() {
        _x = sinyalContoh();
        _fs = 250;
        _hitung();
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
        _x = x;
        _hitung();
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
        backgroundColor: const Color(0xFFF7F8F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          titleSpacing: 16,
          title: const Text('Deteksi Artefak EKG',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: tinta)),
          bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Color(0xFFEDEFEE))),
        ),
        body: _beranda(),
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
    final persenBersih = durasi == 0 ? 0.0 : (1 - durArt / durasi).clamp(0.0, 1.0);
    String statusHr(double v) => v == 0 ? '-' : (v < 60 ? 'Rendah' : (v > 100 ? 'Tinggi' : 'Normal'));
    String ada(int n) => n == 0 ? 'Normal' : 'Perlu perhatian';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      // rekaman
      Container(
        padding: const EdgeInsets.all(16),
        decoration: kartu(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rekaman', style: TextStyle(color: redup, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(_nama, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: tinta)),
          Text(_info, style: const TextStyle(color: redup, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: zaitun, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _muat,
                child: const Text('Muat rekaman'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: zaitun,
                    side: const BorderSide(color: zaitun),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _contoh,
                child: const Text('Pakai contoh'),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // kualitas sinyal + saklar model
      Container(
        padding: const EdgeInsets.all(16),
        decoration: kartu(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Kualitas sinyal', style: TextStyle(fontWeight: FontWeight.w700, color: tinta))),
            Text('${(persenBersih * 100).round()}% bersih', style: const TextStyle(fontWeight: FontWeight.w700, color: zaitun)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: persenBersih, minHeight: 8, color: zaitun, backgroundColor: const Color(0xFFF2BDBD)),
          ),
          const SizedBox(height: 8),
          Text('${_h.artefak.length} segmen artefak, ${durArt.toStringAsFixed(1)} dari ${durasi.toStringAsFixed(0)} detik',
              style: const TextStyle(color: redup, fontSize: 12.5)),
          const Divider(height: 24, color: Color(0xFFEDEFEE)),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bersihkan dengan model CDAE', style: TextStyle(fontWeight: FontWeight.w600, color: tinta)),
                Text(
                    _model.isEmpty
                        ? 'Memuat model...'
                        : (_pakaiModel ? 'Artefak dibersihkan lalu ikut dihitung' : 'Artefak dibuang dari perhitungan'),
                    style: const TextStyle(color: redup, fontSize: 12)),
              ]),
            ),
            Switch(
              value: _pakaiModel,
              activeTrackColor: zaitun,
              onChanged: _model.isEmpty
                  ? null
                  : (v) => setState(() {
                        _pakaiModel = v;
                        _hitung();
                      }),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // grafik
      Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        decoration: kartu(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Sinyal EKG', style: TextStyle(fontWeight: FontWeight.w700, color: tinta)),
          ),
          AspectRatio(aspectRatio: 1.45, child: CustomPaint(painter: Grafik(_h))),
        ]),
      ),
      const SizedBox(height: 20),

      // hasil pemeriksaan
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Hasil Pemeriksaan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tinta)),
      ),
      Container(
        decoration: kartu(),
        child: Column(children: [
          _Hasil('Rata-rata detak jantung', '${s.hrRata.round()} bpm', statusHr(s.hrRata)),
          _Hasil('Detak tertinggi', '${s.hrMax.round()} bpm', statusHr(s.hrMax)),
          _Hasil('Detak terendah', '${s.hrMin.round()} bpm', statusHr(s.hrMin)),
          _Hasil('Takikardia (> 100 bpm)', '${s.tachy} interval · ${s.persenTachy.toStringAsFixed(0)}%', ada(s.tachy)),
          _Hasil('Bradikardia (< 60 bpm)', '${s.brady} interval · ${s.persenBrady.toStringAsFixed(0)}%', ada(s.brady)),
          _Hasil('PVC', '${_h.hitung('PVC')} beat', ada(_h.hitung('PVC'))),
          _Hasil('PAC', '${_h.hitung('PAC')} beat', ada(_h.hitung('PAC')), terakhir: true),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text('Dihitung dari ${s.totalBeat} detak dan ${s.jumlahInterval} interval R-R. Hasil ini bukan diagnosis.',
            style: const TextStyle(color: redup, fontSize: 11.5)),
      ),
      const SizedBox(height: 20),

      // segmen artefak
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Segmen Artefak', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tinta)),
      ),
      Container(
        decoration: kartu(),
        child: Column(children: [
          if (_h.artefak.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tidak ada artefak. Seluruh rekaman dihitung.', style: TextStyle(color: tinta))),
          for (final (i, a) in _h.artefak.indexed)
            _Hasil(
              'Segmen ${i + 1}',
              '${a.mulai.toStringAsFixed(2)} – ${a.selesai.toStringAsFixed(2)} detik',
              _h.dibersihkan ? 'Dibersihkan ${(_h.modelPerSegmen[i] ?? '').toUpperCase()}' : 'Dibuang',
              netral: true,
              terakhir: i == _h.artefak.length - 1,
            ),
        ]),
      ),
    ]);
  }
}

class _Hasil extends StatelessWidget {
  final String label, nilai, status;
  final bool terakhir, netral;
  const _Hasil(this.label, this.nilai, this.status, {this.terakhir = false, this.netral = false});
  @override
  Widget build(BuildContext context) {
    final baik = status == 'Normal';
    final bg = netral ? const Color(0xFFF1F3F2) : (baik ? zaitunMuda : const Color(0xFFFDECEA));
    final fg = netral ? redup : (baik ? zaitun : const Color(0xFFB3261E));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration:
          BoxDecoration(border: terakhir ? null : const Border(bottom: BorderSide(color: Color(0xFFEDEFEE)))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: redup, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700, color: tinta, fontSize: 15)),
          ]),
        ),
        if (status != '-')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
      ]),
    );
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
  final IconData ikon; // tidak ditampilkan, dibiarkan agar pemanggil tidak berubah
  final String label, nilai;
  const _Detail({required this.ikon, required this.label, required this.nilai});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: redup, fontSize: 12.5)),
        const SizedBox(height: 2),
        Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700, color: tinta, fontSize: 16)),
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

    // sinyal EKG, garis hitam tipis. Bila sudah dibersihkan model: sinyal asli abu,
    // hasil model hijau tua di area artefak.
    Path jalur(List<double> sig) {
      final p = Path();
      final perPx = sig.length / w;
      for (var k = 0; k < w; k++) {
        final a = (k * perPx).floor(), z = ((k + 1) * perPx).ceil().clamp(a + 1, sig.length);
        var mn = sig[a], mx = sig[a];
        for (var i = a; i < z; i++) {
          if (sig[i] < mn) mn = sig[i];
          if (sig[i] > mx) mx = sig[i];
        }
        final x = kiri + k.toDouble();
        if (k == 0) p.moveTo(x, py(mx));
        p.lineTo(x, py(mx));
        p.lineTo(x, py(mn));
      }
      return p;
    }

    final gaya = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    if (h.dibersihkan) {
      c.drawPath(jalur(h.sinyalAsli!), gaya..color = const Color(0x55000000));
      c.save();
      final luar = Path()..addRect(Rect.fromLTWH(kiri, atas, w, ht));
      for (final s in h.artefak) {
        luar.addRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht));
      }
      luar.fillType = PathFillType.evenOdd;
      c.clipPath(luar);
      c.drawPath(jalur(h.sinyal), gaya..color = Colors.black);
      c.restore();
      c.save();
      final dalam = Path();
      for (final s in h.artefak) {
        dalam.addRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht));
      }
      c.clipPath(dalam);
      c.drawPath(jalur(h.sinyal), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xFF1E6B45));
      c.restore();
    } else {
      c.drawPath(jalur(h.sinyal), gaya..color = Colors.black);
    }

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
