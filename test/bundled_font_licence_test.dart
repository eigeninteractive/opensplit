import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// That the fonts this app redistributes travel with their licence.
void main() {
  final directory = Directory('assets/google_fonts');
  final licence = File('${directory.path}/LICENSE').readAsStringSync();

  test('every bundled face has its notice in the bundled licence', () {
    final faces = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.ttf'))
        .toList();

    expect(faces, isNotEmpty, reason: 'no fonts found — has the bundle moved?');

    for (final face in faces) {
      final notice = _copyright(face.readAsBytesSync());
      expect(
        notice,
        isNotNull,
        reason: '${face.path} carries no copyright in its name table',
      );
      // Wrapped in the licence file for width, so the comparison is on the
      // sentence that names the holder rather than on the whole line.
      final holder = notice!.split('(').first.trim();
      expect(
        licence,
        contains(holder),
        reason:
            '${face.path} ships without its notice — add "$notice" to '
            'assets/google_fonts/LICENSE',
      );
    }
  });

  test('the licence text is present, not linked', () {
    // Clause 2 is the one being satisfied, and a URL does not satisfy it: the
    // file has to accompany the fonts.
    expect(licence, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(
      licence,
      contains('must be distributed entirely under this license'),
    );
    expect(licence, contains('THE FONT SOFTWARE IS PROVIDED "AS IS"'));
  });
}

/// The `copyright` string (name ID 0) from a TrueType file's name table.
String? _copyright(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);

  for (var i = 0; i < tables; i++) {
    final entry = 12 + 16 * i;
    final tag = String.fromCharCodes(bytes.sublist(entry, entry + 4));
    if (tag != 'name') continue;

    final start = data.getUint32(entry + 8);
    final records = data.getUint16(start + 2);
    final strings = start + data.getUint16(start + 4);

    for (var record = 0; record < records; record++) {
      final at = start + 6 + 12 * record;
      final platform = data.getUint16(at);
      final nameId = data.getUint16(at + 6);
      if (nameId != 0) continue;

      final length = data.getUint16(at + 8);
      final offset = strings + data.getUint16(at + 10);
      final raw = bytes.sublist(offset, offset + length);
      // Platform 3 is Windows, whose strings are UTF-16BE; platform 1 is
      // Macintosh, which for these is plain ASCII. Google's fonts carry both.
      return platform == 3
          ? String.fromCharCodes([
              for (var j = 0; j + 1 < raw.length; j += 2)
                raw[j] << 8 | raw[j + 1],
            ])
          : String.fromCharCodes(raw);
    }
  }
  return null;
}
