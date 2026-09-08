import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/utils/pdf_text.dart';
import 'package:throwlab/utils/schedule_parser.dart';

/// A PDF small enough to read, built the way a generator writes one: a
/// header, numbered objects, and streams that may or may not be deflated.
class _Pdf {
  final List<int> _out = [];
  int _objects = 0;

  _Pdf() {
    _ascii('%PDF-1.4\n');
  }

  void _ascii(String text) => _out.addAll(latin1.encode(text));

  int object(String dict, {List<int>? stream}) {
    final number = ++_objects;
    _ascii('$number 0 obj\n$dict\n');
    if (stream != null) {
      _ascii('stream\n');
      _out.addAll(stream);
      _ascii('\nendstream\n');
    }
    _ascii('endobj\n');
    return number;
  }

  Uint8List done() {
    _ascii('%%EOF\n');
    return Uint8List.fromList(_out);
  }
}

/// A one-page PDF in a plain font, showing [content].
Uint8List onePage(String content, {bool compress = false}) {
  final pdf = _Pdf();
  final font = pdf.object(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final body = latin1.encode(content);
  final stream = pdf.object(
      compress ? '<< /Filter /FlateDecode >>' : '<< >>',
      stream: compress ? ZLibCodec().encode(body) : body);
  pdf.object('<< /Type /Page /Resources << /Font << /F1 $font 0 R >> >> '
      '/Contents $stream 0 R >>');
  return pdf.done();
}

void main() {
  test('reads a line of text out of an uncompressed page', () {
    final text = pdfText(onePage('BT /F1 12 Tf 72 700 Td (Tiger Relays) Tj ET'));
    expect(text, 'Tiger Relays');
  });

  test('inflates a deflated content stream', () {
    final text = pdfText(
        onePage('BT /F1 12 Tf 72 700 Td (Tiger Relays) Tj ET', compress: true));
    expect(text, 'Tiger Relays');
  });

  test('breaks a line where the text moves down the page', () {
    final text = pdfText(onePage('BT /F1 12 Tf 72 700 Td (Row one) Tj '
        '0 -14 Td (Row two) Tj ET'));
    expect(text, 'Row one\nRow two');
  });

  test('marks a jump along the line as a column', () {
    final text = pdfText(onePage(
        'BT /F1 12 Tf 72 700 Td (3/13) Tj 120 0 Td (Tiger Relays) Tj ET'));
    expect(text, '3/13  Tiger Relays');
  });

  test('spaces words a generator kerned apart', () {
    final text = pdfText(
        onePage('BT /F1 12 Tf 72 700 Td [(Tiger) -400 (Relays)] TJ ET'));
    expect(text, 'Tiger Relays');
  });

  test('reads octal escapes and hex strings', () {
    final text = pdfText(onePage('BT /F1 12 Tf 72 700 Td (Caf\\351) Tj '
        '0 -14 Td <4F70656E> Tj ET'));
    expect(text, 'Café\nOpen');
  });

  group('a subset font', () {
    Uint8List identityPage(String content, {bool withMap = true}) {
      final pdf = _Pdf();
      // A subset font indexes its glyphs from one and says what they mean
      // here: two spelled out, a run of three, and a pair listed.
      const cmap = '''
/CIDInit /ProcSet findresource begin
begincmap
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<0001> <0054>
<0002> <0069>
endbfchar
2 beginbfrange
<0003> <0005> <0061>
<0006> <0007> [<0065> <006E>]
endbfrange
endcmap
''';
      final toUnicode =
          pdf.object('<< >>', stream: latin1.encode(cmap));
      final font = pdf.object('<< /Type /Font /Subtype /Type0 '
          '/Encoding /Identity-H '
          '${withMap ? '/ToUnicode $toUnicode 0 R ' : ''}>>');
      final stream =
          pdf.object('<< >>', stream: latin1.encode(content));
      pdf.object('<< /Type /Page /Resources << /Font << /F1 $font 0 R >> >> '
          '/Contents $stream 0 R >>');
      return pdf.done();
    }

    test('is read through the table it ships', () {
      final text = pdfText(identityPage('BT /F1 12 Tf '
          '72 700 Td <00010002000400020003> Tj '
          '0 -14 Td <000100060007> Tj ET'));
      expect(text, 'Tibia\nTen');
    });

    test('is dropped rather than guessed at when it ships none', () {
      final text = pdfText(identityPage(
          'BT /F1 12 Tf 72 700 Td <00010002000400020003> Tj ET',
          withMap: false));
      expect(text, isNull);
    });
  });

  group('what it will not pretend to read', () {
    test('a file that is not a PDF', () {
      expect(pdfText(Uint8List.fromList(latin1.encode('not a pdf'))), isNull);
    });

    test('a scan, which has a picture where the words should be', () {
      final pdf = _Pdf();
      final image = pdf.object('<< /Type /XObject /Subtype /Image '
          '/Filter /DCTDecode /Width 100 /Height 100 >>',
          stream: List.filled(64, 0xFF));
      pdf.object('<< /Type /Page /Resources << /XObject << /Im0 $image 0 R >> '
          '>> >>');
      expect(pdfText(pdf.done()), isNull);
    });
  });

  test('hands a schedule over to the parser in one piece', () {
    final text = pdfText(onePage('BT /F1 12 Tf '
        '72 720 Td (2027 Outdoor Schedule) Tj '
        '0 -20 Td (3/13) Tj 120 0 Td (Tiger Relays) Tj 200 0 Td (Auburn) Tj '
        '-320 -20 Td (4/10) Tj 120 0 Td (County Champs) Tj '
        '200 0 Td (Sportcity) Tj ET'));
    final found = parseSchedule(text!, today: DateTime(2026, 9, 8));
    expect(found.map((c) => c.name), ['Tiger Relays', 'County Champs']);
    expect(found.map((c) => c.venue), ['Auburn', 'Sportcity']);
    expect(found.first.date, DateTime(2027, 3, 13));
  });
}
