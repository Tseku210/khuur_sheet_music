// Copies one preset, with only the instruments and samples it uses, out of a
// SoundFont 2 file into a new, smaller one saved as bank 0, program 0.
//
//   dart run tool/extract_sf2_preset.dart <in.sf2> <out.sf2> <bank> <program>
//
// assets/soundfonts/piano.sf2 was made from GeneralUser GS v2.0.3 with
// bank 0, program 0 (Acoustic Grand Piano).

import 'dart:io';
import 'dart:typed_data';

const _instrumentGen = 41;
const _sampleIdGen = 53;
const _samplePadding = 46;

void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln(
        'usage: extract_sf2_preset.dart <in.sf2> <out.sf2> <bank> <program>');
    exit(64);
  }
  final input = SoundFont.parse(File(args[0]).readAsBytesSync());
  final output = input.extract(int.parse(args[2]), int.parse(args[3]));
  File(args[1]).writeAsBytesSync(output);
  stdout.writeln('${args[1]}: ${output.length} bytes');
}

class Chunk {
  Chunk(this.id, this.data);
  final String id;
  final Uint8List data;
}

class SoundFont {
  SoundFont(this.info, this.smpl, this.pdta);

  factory SoundFont.parse(Uint8List bytes) {
    final riff = _chunks(bytes, 12);
    Map<String, Chunk> list(String type) => {
          for (final c in riff.where((c) =>
              c.id == 'LIST' &&
              String.fromCharCodes(c.data.sublist(0, 4)) == type))
            for (final sub in _chunks(c.data, 4)) sub.id: sub,
        };
    final info = [
      for (final c in riff.where((c) =>
          c.id == 'LIST' &&
          String.fromCharCodes(c.data.sublist(0, 4)) == 'INFO'))
        ..._chunks(c.data, 4),
    ];
    return SoundFont(info, list('sdta')['smpl']!.data, list('pdta'));
  }

  final List<Chunk> info;
  final Uint8List smpl;
  final Map<String, Chunk> pdta;

  List<Uint8List> _records(String id, int size) {
    final data = pdta[id]!.data;
    return [
      for (var i = 0; i < data.length; i += size) data.sublist(i, i + size),
    ];
  }

  Uint8List extract(int bank, int program) {
    final phdr = _records('phdr', 38);
    final pbag = _records('pbag', 4);
    final pmod = _records('pmod', 10);
    final pgen = _records('pgen', 4);
    final inst = _records('inst', 22);
    final ibag = _records('ibag', 4);
    final imod = _records('imod', 10);
    final igen = _records('igen', 4);
    final shdr = _records('shdr', 46);

    final p = [
      for (var i = 0; i < phdr.length - 1; i++)
        if (_u16(phdr[i], 20) == program && _u16(phdr[i], 22) == bank) i,
    ].single;

    final instruments = <int>[];
    final presetZones = _zones(phdr, 24, p, pbag, pgen, pmod);
    for (final zone in presetZones) {
      for (final gen in zone.gens) {
        if (_u16(gen, 0) == _instrumentGen) {
          final i = _u16(gen, 2);
          if (!instruments.contains(i)) instruments.add(i);
        }
      }
    }

    final samples = <int>[];
    final instrumentZones = [
      for (final i in instruments) _zones(inst, 20, i, ibag, igen, imod),
    ];
    void addSample(int s) {
      if (samples.contains(s)) return;
      samples.add(s);
      final type = _u16(shdr[s], 44);
      if (type != 1 && type & 0x8000 == 0) addSample(_u16(shdr[s], 42));
    }

    for (final zones in instrumentZones) {
      for (final zone in zones) {
        for (final gen in zone.gens) {
          if (_u16(gen, 0) == _sampleIdGen) addSample(_u16(gen, 2));
        }
      }
    }

    final newSmpl = BytesBuilder();
    final newShdr = BytesBuilder();
    for (final s in samples) {
      final h = Uint8List.fromList(shdr[s]);
      final start = _u32(h, 20);
      final end = _u32(h, 24);
      final offset = newSmpl.length ~/ 2 - start;
      newSmpl
        ..add(smpl.sublist(start * 2, end * 2))
        ..add(Uint8List(_samplePadding * 2));
      for (final field in [20, 24, 28, 32]) {
        _setU32(h, field, _u32(h, field) + offset);
      }
      if (_u16(h, 44) != 1 && _u16(h, 44) & 0x8000 == 0) {
        _setU16(h, 42, samples.indexOf(_u16(h, 42)));
      }
      newShdr.add(h);
    }
    newShdr.add(_terminal(46, 'EOS'));

    final newPdta = <String, BytesBuilder>{
      for (final id in [
        'phdr',
        'pbag',
        'pmod',
        'pgen',
        'inst',
        'ibag',
        'imod',
        'igen'
      ])
        id: BytesBuilder(),
    };
    void writeZones(List<Zone> zones, String bag, String gen, String mod,
        int remapGen, List<int> targets) {
      for (final zone in zones) {
        newPdta[bag]!
          ..add(_u16Bytes(newPdta[gen]!.length ~/ 4))
          ..add(_u16Bytes(newPdta[mod]!.length ~/ 10));
        for (final g in zone.gens) {
          final copy = Uint8List.fromList(g);
          if (_u16(copy, 0) == remapGen) {
            _setU16(copy, 2, targets.indexOf(_u16(copy, 2)));
          }
          newPdta[gen]!.add(copy);
        }
        for (final m in zone.mods) {
          newPdta[mod]!.add(m);
        }
      }
    }

    final header = Uint8List.fromList(phdr[p]);
    _setU16(header, 20, 0);
    _setU16(header, 22, 0);
    _setU16(header, 24, 0);
    newPdta['phdr']!.add(header);
    writeZones(
        presetZones, 'pbag', 'pgen', 'pmod', _instrumentGen, instruments);
    newPdta['phdr']!.add(_terminal(38, 'EOP')
      ..buffer.asByteData().setUint16(24, presetZones.length, Endian.little));

    for (var n = 0; n < instruments.length; n++) {
      final h = Uint8List.fromList(inst[instruments[n]]);
      _setU16(h, 20, newPdta['ibag']!.length ~/ 4);
      newPdta['inst']!.add(h);
      writeZones(
          instrumentZones[n], 'ibag', 'igen', 'imod', _sampleIdGen, samples);
    }
    newPdta['inst']!.add(_terminal(22, 'EOI')
      ..buffer
          .asByteData()
          .setUint16(20, newPdta['ibag']!.length ~/ 4, Endian.little));

    for (final (bag, gen, mod) in [
      ('pbag', 'pgen', 'pmod'),
      ('ibag', 'igen', 'imod'),
    ]) {
      newPdta[bag]!
        ..add(_u16Bytes(newPdta[gen]!.length ~/ 4))
        ..add(_u16Bytes(newPdta[mod]!.length ~/ 10));
      newPdta[gen]!.add(Uint8List(4));
      newPdta[mod]!.add(Uint8List(10));
    }

    final name = String.fromCharCodes(header.sublist(0, 20))
        .replaceAll('\x00', '')
        .trim();
    final infoOut = [
      for (final c in info)
        if (c.id == 'INAM')
          Chunk('INAM', _zstr('$name (from GeneralUser GS v2.0.3)'))
        else
          c,
    ];

    return _riff('sfbk', [
      _list('INFO', infoOut),
      _list('sdta', [Chunk('smpl', newSmpl.takeBytes())]),
      _list('pdta', [
        for (final id in [
          'phdr',
          'pbag',
          'pmod',
          'pgen',
          'inst',
          'ibag',
          'imod',
          'igen'
        ])
          Chunk(id, newPdta[id]!.takeBytes()),
        Chunk('shdr', newShdr.takeBytes()),
      ]),
    ]);
  }
}

class Zone {
  Zone(this.gens, this.mods);
  final List<Uint8List> gens;
  final List<Uint8List> mods;
}

List<Zone> _zones(List<Uint8List> headers, int bagField, int index,
    List<Uint8List> bags, List<Uint8List> gens, List<Uint8List> mods) {
  final first = _u16(headers[index], bagField);
  final last = _u16(headers[index + 1], bagField);
  return [
    for (var b = first; b < last; b++)
      Zone(
        gens.sublist(_u16(bags[b], 0), _u16(bags[b + 1], 0)),
        mods.sublist(_u16(bags[b], 2), _u16(bags[b + 1], 2)),
      ),
  ];
}

List<Chunk> _chunks(Uint8List bytes, int offset) {
  final view = ByteData.sublistView(bytes);
  final chunks = <Chunk>[];
  var i = offset;
  while (i + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(i, i + 4));
    final size = view.getUint32(i + 4, Endian.little);
    chunks.add(Chunk(id, bytes.sublist(i + 8, i + 8 + size)));
    i += 8 + size + (size.isOdd ? 1 : 0);
  }
  return chunks;
}

Chunk _list(String type, List<Chunk> children) {
  final b = BytesBuilder()..add(type.codeUnits);
  for (final c in children) {
    b
      ..add(c.id.codeUnits)
      ..add(_u32Bytes(c.data.length))
      ..add(c.data);
    if (c.data.length.isOdd) b.addByte(0);
  }
  return Chunk('LIST', b.takeBytes());
}

Uint8List _riff(String type, List<Chunk> children) {
  final body = _list(type, children).data;
  return (BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(_u32Bytes(body.length))
        ..add(body))
      .takeBytes();
}

Uint8List _terminal(int size, String name) =>
    Uint8List(size)..setRange(0, name.length, name.codeUnits);

Uint8List _zstr(String s) {
  final length = s.length + 1;
  return Uint8List(length + length % 2)..setRange(0, s.length, s.codeUnits);
}

int _u16(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint16(at, Endian.little);
int _u32(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint32(at, Endian.little);
void _setU16(Uint8List b, int at, int v) =>
    ByteData.sublistView(b).setUint16(at, v, Endian.little);
void _setU32(Uint8List b, int at, int v) =>
    ByteData.sublistView(b).setUint32(at, v, Endian.little);
Uint8List _u16Bytes(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32Bytes(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
