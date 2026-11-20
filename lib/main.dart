import 'dart:math';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
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
  String _nama = 'Sinyal buatan';
  String _info = '20 detik, 250 Hz';
  final Map<String, Cdae> _model = {};
  Mtb? _mtb; // model multitask: klasifikasi jenis noise
  bool _pakaiModel = false;
  bool _lihatMentah = false; // pratinjau: sebelum (mentah) atau sesudah dibersihkan

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
    try {
      _mtb = Mtb.dariBytes(await rootBundle.load('assets/model/mtb.bin'));
    } catch (_) {} // tanpa mtb.bin, jenis noise memakai aturan cadangan
    if (mounted) setState(_hitung);
  }

  void _hitung() => _h = analisis(_x, _fs, model: _pakaiModel ? _model : const {}, mtb: _mtb);

  /// Label jenis noise segmen [i]; bila dari model, disertai peluangnya.
  String _jenisTeks(int i) {
    final j = _h.jenis[i];
    if (!_h.jenisDariModel || _h.peluangJenis[i].isEmpty) return j.join(' + ');
    final p = _h.peluangJenis[i];
    return j.map((e) => '$e ${(p[Mtb.kelas.indexOf(e)] * 100).round()}%').join(' + ');
  }

  /// Rekaman panjang dipotong 60 detik pertama supaya tetap ringan di HP.
  (List<double>, String) _potong(List<double> x, double fs) {
    final maks = (60 * fs).round();
    return x.length > maks ? (x.sublist(0, maks), ', 60 detik pertama') : (x, '');
  }

  void _pasang(List<double> x, double fs, String nama, [String tambahan = '']) {
    final (y, potong) = _potong(x, fs);
    setState(() {
      _x = y;
      _fs = fs;
      _hitung();
      _nama = nama;
      _info = '${(y.length / fs).toStringAsFixed(0)} detik, ${fs.round()} Hz$tambahan$potong';
    });
  }

  /// Unduh sinyal hasil filter dan rekonstruksi (float32) untuk tahap machine learning.
  void _unduh() {
    final bytes = keBinFloat32(_h.sinyal);
    final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'application/octet-stream'));
    final nama = '${_nama.split('.').first.replaceAll(' ', '_')}_bersih_${_fs.round()}Hz.bin';
    html.AnchorElement(href: url)
      ..download = nama
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static const _pilihanContoh = [
    ('Sinyal buatan', 'Noise gerak, otot, dan baseline', ''),
    ('INCART bersih', 'Rekaman asli tanpa noise tambahan', 'incart_I01_bersih'),
    ('INCART + noise elektroda (EM)', 'Noise di 3 sampai 6 s dan 12,5 sampai 15 s', 'incart_I01_em'),
    ('INCART + noise otot (MA)', 'Noise di 3 sampai 6 s dan 12,5 sampai 15 s', 'incart_I01_ma'),
    ('INCART + baseline wander (BW)', 'Noise di 3 sampai 6 s dan 12,5 sampai 15 s', 'incart_I01_bw'),
    ('INCART + noise campuran', 'BW+EM di 3 sampai 6 s, MA+EM di 12,5 sampai 15 s', 'incart_I01_campur'),
    ('INCART + noise berat (-6 dB)', 'MA dan EM jauh lebih kuat dari sinyal', 'incart_I01_berat'),
  ];

  Future<void> _contoh() async {
    final pilih = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rekaman contoh', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: hijauGelap)),
            const SizedBox(height: 4),
            const Text('INCART dan noise NSTDB dari PhysioNet, 257 Hz, 20 detik.', style: TextStyle(color: redup, fontSize: 12.5)),
            const SizedBox(height: 14),
            for (final (i, (judul, ket, _)) in _pilihanContoh.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _nama == judul ? const Color(0xFFDDEFE3) : const Color(0xFFF2F5F3),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(ctx, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(judul, style: const TextStyle(fontWeight: FontWeight.w700, color: hijauGelap)),
                            Text(ket, style: const TextStyle(color: redup, fontSize: 12)),
                          ]),
                        ),
                        if (_nama == judul) const Icon(Icons.check_rounded, color: zaitun),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (pilih == null) return;
    final (judul, _, file) = _pilihanContoh[pilih];
    if (file.isEmpty) {
      _pasang(sinyalContoh(), 250, judul);
    } else {
      final bd = await rootBundle.load('contoh/$file.bin');
      _pasang(bacaBinFloat32(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes)), 257, judul);
    }
  }

  /// Muat rekaman: .bin (float32 mentah), pasangan .hea + .dat (PhysioNet), atau CSV.
  Future<void> _muat() async {
    try {
      final pilih = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['bin', 'hea', 'dat', 'csv', 'txt'], withData: true, allowMultiple: true);
      final files = pilih?.files.where((f) => f.bytes != null).toList() ?? [];
      if (files.isEmpty) return;
      String ext(PlatformFile f) => f.name.split('.').last.toLowerCase();
      final hea = files.where((f) => ext(f) == 'hea').firstOrNull;
      if (hea != null) {
        final dat = files.where((f) => ext(f) == 'dat').firstOrNull;
        if (dat == null) throw 'pilih file .hea dan .dat sekaligus';
        final (x, fs, lead) = bacaPhysionet(utf8.decode(hea.bytes!, allowMalformed: true), dat.bytes!);
        if (x.length < fs * 2) throw 'data terlalu pendek';
        _pasang(x, fs, hea.name.split('.').first, ', lead $lead');
        return;
      }
      final f = files.first;
      final fs = await _tanyaFs(f.name);
      if (fs == null) return;
      final x = ext(f) == 'bin' || ext(f) == 'dat'
          ? bacaBinFloat32(f.bytes!)
          : bacaCsv(utf8.decode(f.bytes!, allowMalformed: true));
      if (x.length < fs * 2) throw 'data terlalu pendek';
      _pasang(x, fs, f.name);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
    }
  }

  Future<double?> _tanyaFs(String namaFile) {
    // alat CardioSense: single lead, sekitar 267 Hz
    final c = TextEditingController(text: '267');
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
          Text('$namaFile. File .bin dibaca sebagai float32 mentah satu lead (mV). Untuk format PhysioNet, pilih file .hea dan .dat sekaligus.',
              style: const TextStyle(color: redup, fontSize: 13)),
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
                teks: 'Lanjut',
                ikon: Icons.upload_file_rounded,
                onTap: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.')))),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFEFF3F1),
        body: SafeArea(child: _beranda()),
      );

  Widget _judul(String t, [Widget? ekor]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tinta))),
          if (ekor != null) ekor,
        ]),
      );

  /// Tahapan seperti di halaman detail rekaman: Rekaman, lalu bagian pembersihan sinyal
  /// (filter, deteksi artefak, jenis noise, penanganan), lalu Prediksi oleh model ML.
  Widget _tahapan() {
    final rekon = _h.penanganan.where((p) => p.startsWith('Direkonstruksi')).length;
    final buang = _h.penanganan.where((p) => p == 'Dibuang').length;
    final lurus = _h.penanganan.where((p) => p == 'Diluruskan filter').length;
    final daftar = [
      ('Rekaman', '$_nama, $_info', 'Selesai'),
      ('Filter', 'Band-pass 0,5-40 Hz dan notch 50 Hz, garis dasar lurus', 'Selesai'),
      ('Deteksi artefak', _h.artefak.isEmpty ? 'Tidak ada segmen noise' : '${_h.artefak.length} segmen noise ditemukan', 'Selesai'),
      ('Jenis noise', 'Aturan sinyal sementara, menunggu model dari Zaskia', 'Sementara'),
      (
        'Penanganan',
        _h.artefak.isEmpty ? 'Tidak ada yang perlu ditangani' : '$lurus diluruskan, $rekon direkonstruksi, $buang dibuang',
        'Selesai'
      ),
      ('Prediksi aritmia', 'Sinyal bersih diteruskan ke model machine learning', 'Berikutnya'),
    ];
    Color warna(String st) => switch (st) {
          'Selesai' => zaitun,
          'Sementara' => const Color(0xFFB7791F),
          _ => redup,
        };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tahapan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: hijauGelap)),
        const SizedBox(height: 10),
        for (final (i, (judul, isi, st)) in daftar.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 26,
                child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: warna(st), fontSize: 14)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(judul, style: const TextStyle(fontWeight: FontWeight.w700, color: hijauGelap)),
                  const SizedBox(height: 2),
                  Text(isi, style: const TextStyle(color: redup, fontSize: 12.5, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: warna(st).withOpacity(.12), borderRadius: BorderRadius.circular(20)),
                child: Text(st, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: warna(st))),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _beranda() {
    // Sebelum: artefak ikut dihitung; Sesudah: segmen artefak dibuang
    final s = _lihatMentah ? _h.statSebelum : _h.stat;
    final durasi = _h.sinyal.length / _h.fs;
    final durArt = _h.dibuang.fold(0.0, (a, g) => a + g.selesai - g.mulai);
    final persenBersih = durasi == 0 ? 0.0 : (1 - durArt / durasi).clamp(0.0, 1.0);
    String statusHr(double v) => v == 0 ? '-' : (v < 60 ? 'Rendah' : (v > 100 ? 'Tinggi' : 'Normal'));
    String ada(int n) => n == 0 ? 'Normal' : 'Perlu perhatian';

    // persentase bersih per blok 2 detik untuk grafik batang
    final blok = durasi > 40 ? 10.0 : 2.0;
    final batang = <double>[];
    for (var t = 0.0; t < durasi - 1e-9; t += blok) {
      final z = min(durasi, t + blok);
      var kotor = 0.0;
      for (final a in _h.dibuang) {
        kotor += max(0.0, min(z, a.selesai) - max(t, a.mulai));
      }
      batang.add(1 - kotor / (z - t));
    }

    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 32), children: [
      // kepala: judul besar + tombol bulat
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Expanded(
          child: Text('Pemeriksaan\nEKG', style: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, color: hijauGelap)),
        ),
        _TombolBulat(ikon: Icons.upload_file_rounded, onTap: _muat),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nama, style: const TextStyle(color: hijauGelap, fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(_info, style: const TextStyle(color: redup, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 12),
        _Pil(teks: 'Pilih contoh', onTap: _contoh),
      ]),
      const SizedBox(height: 26),

      // kualitas sinyal: angka besar + batang per blok
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Expanded(child: Text('Kualitas sinyal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: hijauGelap))),
        Text('${(persenBersih * 100).round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: zaitun)),
      ]),
      const SizedBox(height: 14),
      SizedBox(height: 150, child: CustomPaint(painter: _Batang(batang, persenBersih), size: Size.infinite)),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < batang.length; i++)
          Expanded(
            child: Center(
              child: Text('${(i * blok).toStringAsFixed(0)}s', style: const TextStyle(fontSize: 10.5, color: redup)),
            ),
          ),
      ]),
      const SizedBox(height: 26),

      // tiga kotak hasil utama
      const Center(child: Text('Hasil utama', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: hijauGelap))),
      const SizedBox(height: 12),
      Row(children: [
        _Kotak(warna: const Color(0xFFDDEFE3), judul: 'Detak\njantung', nilai: '${s.hrRata.round()}', satuan: 'bpm'),
        const SizedBox(width: 10),
        _Kotak(warna: const Color(0xFFE6F2EA), judul: 'PVC', nilai: '${_h.hitung('PVC')}', satuan: 'beat'),
        const SizedBox(width: 10),
        _Kotak(warna: const Color(0xFFEFF6F1), judul: 'PAC', nilai: '${_h.hitung('PAC')}', satuan: 'beat'),
      ]),
      if (_h.bahaya.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(22)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Perlu diperiksa segera', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFC62828))),
                const SizedBox(height: 4),
                for (final b in _h.bahaya) Text(b, style: const TextStyle(color: tinta, fontSize: 13, height: 1.4)),
                const SizedBox(height: 4),
                const Text('Penanda awal berbasis aturan, bukan diagnosis.', style: TextStyle(color: redup, fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 22),

      // tahapan: posisi bagian ini di antara Rekaman dan Prediksi
      _tahapan(),
      const SizedBox(height: 22),

      // pratinjau sinyal sebelum / sesudah
      Container(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, bottom: 10),
            child: Row(children: [
              const Expanded(
                child: Text('Pratinjau sinyal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: hijauGelap)),
              ),
              for (final (label, mentah) in const [('Sebelum', true), ('Sesudah', false)])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Material(
                    color: _lihatMentah == mentah ? zaitun : const Color(0xFFF2F5F3),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _lihatMentah = mentah),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _lihatMentah == mentah ? Colors.white : hijauGelap)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          AspectRatio(aspectRatio: 1.45, child: CustomPaint(painter: Grafik(_h, mentah: _lihatMentah))),
        ]),
      ),
      const SizedBox(height: 12),

      // saklar model
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Rekonstruksi artefak ringan', style: TextStyle(fontWeight: FontWeight.w700, color: hijauGelap)),
              const SizedBox(height: 2),
              Text(
                  _model.isEmpty
                      ? 'Memuat model...'
                      : (_pakaiModel
                          ? 'Ringan direkonstruksi decoder CDAE, parah dibuang'
                          : 'Semua artefak yang tersisa setelah filter dibuang'),
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
      ),
      const SizedBox(height: 12),
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _unduh,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Unduh sinyal bersih (.bin)', style: TextStyle(fontWeight: FontWeight.w700, color: hijauGelap)),
                  SizedBox(height: 2),
                  Text('Float32, untuk tahap klasifikasi aritmia', style: TextStyle(color: redup, fontSize: 12)),
                ]),
              ),
              Icon(Icons.download_rounded, color: zaitun),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 26),

      // detail
      const Text('Detail pemeriksaan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: hijauGelap)),
      const SizedBox(height: 12),
      _Baris('Rata-rata detak jantung', '${s.hrRata.round()} bpm', statusHr(s.hrRata)),
      _Baris('Detak tertinggi', '${s.hrMax.round()} bpm', statusHr(s.hrMax)),
      _Baris('Detak terendah', '${s.hrMin.round()} bpm', statusHr(s.hrMin)),
      _Baris('Takikardia (> 100 bpm)', '${s.tachy} interval (${s.persenTachy.toStringAsFixed(0)}%)', ada(s.tachy)),
      _Baris('Bradikardia (< 60 bpm)', '${s.brady} interval (${s.persenBrady.toStringAsFixed(0)}%)', ada(s.brady)),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
        child: Text('Dihitung dari ${s.totalBeat} detak dan ${s.jumlahInterval} interval R-R. Hasil ini bukan diagnosis.',
            style: const TextStyle(color: redup, fontSize: 11.5)),
      ),
      const SizedBox(height: 26),

      // segmen artefak
      const Text('Segmen artefak', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: hijauGelap)),
      const SizedBox(height: 12),
      if (_h.artefak.isEmpty) const _Baris('Tidak ada artefak', 'Seluruh rekaman dihitung', '-'),
      for (final (i, a) in _h.artefak.indexed)
        _Baris(
          'Segmen ${i + 1}: ${_jenisTeks(i)}, ${const {'lurus': 'diluruskan', 'ringan': 'ringan', 'parah': 'parah'}[_h.tingkat[i]]}',
          '${a.mulai.toStringAsFixed(2)} – ${a.selesai.toStringAsFixed(2)} detik',
          _h.penanganan[i],
          netral: true,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
        child: Text(
            _h.jenisDariModel
                ? 'Jenis noise dari model multitask (MTB-CDAE 1 lead): BW = baseline wander, MA = otot, EM = elektroda/gerak. Persen = peluang model.'
                : 'Model jenis noise belum termuat; jenis noise sementara ditentukan dari ciri sinyal.',
            style: const TextStyle(color: redup, fontSize: 11.5)),
      ),
      const SizedBox(height: 26),
    ]);
  }
}

const hijauGelap = Color(0xFF0F3D2A);

class _TombolBulat extends StatelessWidget {
  final IconData ikon;
  final VoidCallback onTap;
  const _TombolBulat({required this.ikon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 54, height: 54, child: Icon(ikon, color: hijauGelap)),
        ),
      );
}

class _Pil extends StatelessWidget {
  final String teks;
  final VoidCallback onTap;
  const _Pil({required this.teks, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(teks, style: const TextStyle(color: hijauGelap, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      );
}

class _Kotak extends StatelessWidget {
  final Color warna;
  final String judul, nilai, satuan;
  const _Kotak({required this.warna, required this.judul, required this.nilai, required this.satuan});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 128,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: warna, borderRadius: BorderRadius.circular(28)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(judul, style: const TextStyle(color: hijauGelap, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
            const Spacer(),
            Text(nilai, style: const TextStyle(color: hijauGelap, fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
            Text(satuan, style: const TextStyle(color: redup, fontSize: 12)),
          ]),
        ),
      );
}

class _Baris extends StatelessWidget {
  final String label, nilai, status;
  final bool netral;
  const _Baris(this.label, this.nilai, this.status, {this.netral = false});
  @override
  Widget build(BuildContext context) {
    final baik = status == 'Normal';
    final bg = netral ? const Color(0xFFF1F4F2) : (baik ? const Color(0xFFDDEFE3) : const Color(0xFFFBE9E7));
    final fg = netral ? redup : (baik ? zaitun : const Color(0xFFB3261E));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: hijauGelap, fontSize: 14)),
            const SizedBox(height: 2),
            Text(nilai, style: const TextStyle(color: redup, fontSize: 13)),
          ]),
        ),
        if (status != '-')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
      ]),
    );
  }
}

/// Grafik batang: persentase sinyal bersih per blok 2 detik, dengan garis rata-rata.
class _Batang extends CustomPainter {
  final List<double> nilai;
  final double rata;
  _Batang(this.nilai, this.rata);

  @override
  void paint(Canvas c, Size size) {
    if (nilai.isEmpty) return;
    const atas = 26.0;
    final lebar = size.width / nilai.length;
    final ht = size.height - atas;
    for (var i = 0; i < nilai.length; i++) {
      final h = max(6.0, nilai[i] * ht);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(i * lebar + lebar * 0.12, size.height - h, lebar * 0.76, h), const Radius.circular(8));
      c.drawRRect(r, Paint()..color = nilai[i] >= 0.999 ? const Color(0xFF1E6B45) : const Color(0xFFD3DCD7));
    }
    // garis rata-rata putus-putus + label gelap
    final y = size.height - rata * ht;
    for (var x = 0.0; x < size.width; x += 6) {
      c.drawLine(Offset(x, y), Offset(x + 3, y), Paint()
        ..color = const Color(0xFF0F3D2A)
        ..strokeWidth = 1);
    }
    final tp = TextPainter(
        text: TextSpan(
            text: 'Rata-rata ${(rata * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr)
      ..layout();
    final kotak = RRect.fromRectAndRadius(Rect.fromLTWH(0, y - tp.height - 10, tp.width + 14, tp.height + 6), const Radius.circular(10));
    c.drawRRect(kotak, Paint()..color = const Color(0xFF0F3D2A));
    tp.paint(c, Offset(7, y - tp.height - 7));
  }

  @override
  bool shouldRepaint(covariant _Batang old) => old.nilai != nilai || old.rata != rata;
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
  final bool mentah; // true: tampilkan rekaman sebelum dibersihkan
  Grafik(this.h, {this.mentah = false});

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
    for (final (k, s) in h.artefak.indexed) {
      final dibuang = h.penanganan[k] == 'Dibuang';
      c.drawRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht),
          Paint()..color = dibuang ? merahArea : const Color(0xFFFBE7E7));
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
    for (final (k, s) in h.artefak.indexed) {
      final teks = h.penanganan[k] == 'Dibuang' ? 'ARTEFAK' : (h.tingkat[k] == 'lurus' ? 'LURUS' : 'REKONSTRUKSI');
      if (px(s.selesai) - px(s.mulai) > (teks.length > 7 ? 60 : 34)) {
        _label(c, teks, Offset((px(s.mulai) + px(s.selesai)) / 2, atas + ht * 0.1), kecil ? 6.5 : 9);
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
    final urutAsli = [...h.sinyalAsli]..sort();
    final asli = [for (final v in h.sinyalAsli) v - urutAsli[urutAsli.length ~/ 2]];
    if (mentah) {
      c.drawPath(jalur(asli), gaya..color = Colors.black);
    } else if (h.dibersihkan) {
      final urut = [...h.sinyalAsli]..sort();
      final tengah = urut[urut.length ~/ 2];
      c.save();
      final dalamAsli = Path();
      for (final (k, s) in h.artefak.indexed) {
        if (h.penanganan[k].startsWith('Direkonstruksi')) dalamAsli.addRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht));
      }
      c.clipPath(dalamAsli);
      c.drawPath(jalur([for (final v in h.sinyalAsli) v - tengah]), gaya..color = const Color(0x55000000));
      c.restore();
      c.save();
      final luar = Path()..addRect(Rect.fromLTWH(kiri, atas, w, ht));
      for (final (k, s) in h.artefak.indexed) {
        if (h.penanganan[k].startsWith('Direkonstruksi')) luar.addRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht));
      }
      luar.fillType = PathFillType.evenOdd;
      c.clipPath(luar);
      c.drawPath(jalur(h.sinyal), gaya..color = Colors.black);
      c.restore();
      c.save();
      final dalam = Path();
      for (final (k, s) in h.artefak.indexed) {
        if (h.penanganan[k].startsWith('Direkonstruksi')) dalam.addRect(Rect.fromLTRB(px(s.mulai), atas, px(s.selesai), atas + ht));
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
      final x = px(i / h.fs), y = py(mentah ? asli[i] : h.sinyal[i]) - 2;
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
  bool shouldRepaint(covariant Grafik old) => old.h != h || old.mentah != mentah;
}
