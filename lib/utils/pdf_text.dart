/// Reading the text out of a PDF, for schedules that arrive as one.
///
/// Deliberately small. A schedule is a page of words in columns, put out by
/// Word, Google Docs or a meet manager, so this handles the part of the
/// format those produce — object streams, Flate compression, the text
/// operators, and the ToUnicode tables a subset font needs to be readable —
/// and gives up honestly on the rest rather than guessing. A PDF that is
/// really a photograph of a schedule has no text in it at all, and comes
/// back null so the caller can say so.
///
/// It reads the objects in the order they were written rather than walking
/// the page tree, which is the order they are laid down in for every
/// generator worth the name.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The text of [bytes], laid out a line at a time, or null when there is
/// none to be had.
///
/// Columns come back separated by a double space, which is what the
/// schedule parser reads as a column rule.
String? pdfText(Uint8List bytes) {
  // One code unit per byte, so an offset into the string is an offset into
  // the file. PDF structure is ASCII; the compressed parts are never
  // scanned as text.
  final raw = String.fromCharCodes(bytes);
  if (!raw.startsWith('%PDF')) return null;

  final objects = _objects(raw);
  final fonts = _fontMaps(raw, objects);
  final page = _Page(fonts);

  for (final object in objects.values) {
    final content = _streamOf(object);
    if (content == null) continue;
    final text = latin1.decode(content, allowInvalid: true);
    if (!text.contains('BT')) continue;
    page.run(text);
  }

  return page.finish();
}

/// Object number to its body, from `obj` to `endobj`.
Map<int, String> _objects(String raw) {
  final objects = <int, String>{};
  for (final match in RegExp(r'(\d+)\s+\d+\s+obj\b').allMatches(raw)) {
    final end = raw.indexOf('endobj', match.end);
    objects[int.parse(match.group(1)!)] =
        raw.substring(match.end, end == -1 ? raw.length : end);
  }
  return objects;
}

/// The bytes of an object's stream, inflated when it was deflated.
///
/// Anything compressed some other way is an image or a font as far as this
/// is concerned, and is skipped.
List<int>? _streamOf(String object) {
  final start = RegExp(r'\bstream\r?\n?').firstMatch(object);
  if (start == null) return null;
  final end = object.indexOf('endstream', start.end);
  if (end == -1) return null;
  final header = object.substring(0, start.start);
  final data = object.substring(start.end, end).codeUnits;

  if (!header.contains('/FlateDecode')) {
    // Uncompressed content is rarer than it used to be, and perfectly
    // readable. A stream filtered any other way is not text.
    return header.contains('/Filter') ? null : data;
  }
  for (final codec in [ZLibCodec(), ZLibCodec(raw: true)]) {
    try {
      return codec.decode(data);
    } catch (_) {
      // Try the other framing before giving this stream up.
    }
  }
  return null;
}

/// What a font's codes mean, per font resource name.
class _FontMap {
  _FontMap(this.codes, this.bytesPerCode, this.readable);

  /// Empty for a font whose codes are its characters, which is most of the
  /// ones that spell out a schedule.
  final Map<int, String> codes;
  final int bytesPerCode;

  /// False for a subset font that never said what its glyphs mean. Its
  /// codes are indexes into a table this can't see, so its text is dropped
  /// rather than emitted as the mojibake it would decode to.
  final bool readable;
}

/// Every font in the file, wired to the ToUnicode table it declares.
///
/// Two pages that both call their first font `/F1` collide here; the first
/// wins. In a schedule that is one document in one font, which is why this
/// is worth doing at all rather than parsing the page tree.
Map<String, _FontMap> _fontMaps(String raw, Map<int, String> objects) {
  final maps = <String, _FontMap>{};

  void wire(String resources) {
    for (final match in RegExp(r'/([A-Za-z0-9#+.\-]+)\s+(\d+)\s+\d+\s+R')
        .allMatches(resources)) {
      final name = match.group(1)!;
      if (maps.containsKey(name)) continue;
      final font = objects[int.parse(match.group(2)!)];
      if (font == null || !font.contains('/Font')) continue;
      final toUnicode =
          RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(font);
      if (toUnicode == null) {
        // A simple font with no table is its own encoding: byte in,
        // character out. A composite one without a table is unreadable.
        maps[name] = _FontMap(const {}, 1, !font.contains('/Type0'));
        continue;
      }
      final stream = objects[int.parse(toUnicode.group(1)!)];
      final cmap = stream == null ? null : _streamOf(stream);
      if (cmap == null) {
        maps[name] = _FontMap(const {}, 1, !font.contains('/Type0'));
        continue;
      }
      maps[name] = _parseCMap(latin1.decode(cmap, allowInvalid: true));
    }
  }

  for (final match in RegExp(r'/Font\s*<<([^>]*)>>').allMatches(raw)) {
    wire(match.group(1)!);
  }
  for (final match in RegExp(r'/Font\s+(\d+)\s+\d+\s+R').allMatches(raw)) {
    final dict = objects[int.parse(match.group(1)!)];
    if (dict != null) wire(dict);
  }
  return maps;
}

/// A ToUnicode CMap: the table a subset font ships so its glyph codes can
/// be read back as words.
_FontMap _parseCMap(String cmap) {
  final codes = <int, String>{};
  var width = 0;

  final space =
      RegExp(r'begincodespacerange(.*?)endcodespacerange', dotAll: true)
          .firstMatch(cmap);
  if (space != null) {
    final first = RegExp(r'<([0-9A-Fa-f]+)>').firstMatch(space.group(1)!);
    if (first != null) width = first.group(1)!.length ~/ 2;
  }

  for (final block
      in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(cmap)) {
    for (final pair in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
        .allMatches(block.group(1)!)) {
      if (width == 0) width = pair.group(1)!.length ~/ 2;
      codes[int.parse(pair.group(1)!, radix: 16)] = _utf16(pair.group(2)!);
    }
  }

  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
      .allMatches(cmap)) {
    final body = block.group(1)!;
    // <lo> <hi> <dst>: the destinations run on from dst.
    for (final run
        in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
            .allMatches(body)) {
      final lo = int.parse(run.group(1)!, radix: 16);
      final hi = int.parse(run.group(2)!, radix: 16);
      final dst = int.parse(run.group(3)!, radix: 16);
      if (width == 0) width = run.group(1)!.length ~/ 2;
      if (hi - lo > 0xFFFF) continue;
      for (var code = lo; code <= hi; code++) {
        codes[code] = String.fromCharCode(dst + code - lo);
      }
    }
    // <lo> <hi> [<a> <b> …]: one destination each, spelled out.
    for (final run
        in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[([^\]]*)\]')
            .allMatches(body)) {
      final lo = int.parse(run.group(1)!, radix: 16);
      if (width == 0) width = run.group(1)!.length ~/ 2;
      var code = lo;
      for (final dst in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(run.group(3)!)) {
        codes[code++] = _utf16(dst.group(1)!);
      }
    }
  }

  return _FontMap(codes, width == 0 ? 2 : width, true);
}

/// A CMap destination: UTF-16BE, however many characters long.
String _utf16(String hex) {
  final units = <int>[];
  for (var i = 0; i + 3 < hex.length; i += 4) {
    units.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  if (units.isEmpty && hex.length >= 2) {
    units.add(int.parse(hex.substring(0, 2), radix: 16));
  }
  return String.fromCharCodes(units);
}

/// How far apart two pieces of text have to be to be on different lines,
/// and how far along one has to jump to be in the next column. Both in text
/// space, which is points for every generator that isn't being clever.
const _lineGap = 1.5;
const _columnGap = 3.0;

/// The page being built up, an operator at a time.
class _Page {
  _Page(this.fonts);

  final Map<String, _FontMap> fonts;
  final StringBuffer _line = StringBuffer();
  final List<String> _lines = [];

  _FontMap? _font;
  double _x = 0;
  double _y = 0;
  double _leading = 0;
  int _kept = 0;

  /// Characters thrown away because the font that spelled them never said
  /// what they meant. A page that is mostly this is not text.
  int _dropped = 0;

  void run(String content) {
    final operands = <Object>[];
    final scanner = _Scanner(content);
    while (true) {
      final token = scanner.next();
      if (token == null) break;
      if (token is _Operator) {
        _apply(token.name, operands);
        operands.clear();
      } else {
        // A content stream can carry more operands than any operator takes;
        // keeping the tail is enough and keeps this bounded.
        if (operands.length > 64) operands.removeAt(0);
        operands.add(token);
      }
    }
  }

  void _apply(String op, List<Object> operands) {
    switch (op) {
      case 'BT':
        _x = 0;
        _y = 0;
        break;
      case 'ET':
        _break();
        break;
      case 'Tf':
        final name =
            operands.length >= 2 ? operands[operands.length - 2] : null;
        if (name is _Name) _font = fonts[name.value] ?? _soleFont();
        break;
      case 'TL':
        _leading = _number(operands, 0) ?? _leading;
        break;
      case 'Td':
      case 'TD':
        final ty = _number(operands, 0) ?? 0;
        final tx = _number(operands, 1) ?? 0;
        if (op == 'TD') _leading = -ty;
        _move(_x + tx, _y + ty);
        break;
      case 'Tm':
        _move(_number(operands, 1) ?? 0, _number(operands, 0) ?? 0);
        break;
      case 'T*':
        _move(_x, _y - _leading);
        break;
      case 'Tj':
      case '\'':
      case '"':
        if (op != 'Tj') _move(_x, _y - _leading);
        final text = operands.isEmpty ? null : operands.last;
        if (text is _Str) _write(text);
        break;
      case 'TJ':
        final array = operands.isEmpty ? null : operands.last;
        if (array is List<Object>) {
          for (final part in array) {
            if (part is _Str) {
              _write(part);
            } else if (part is num && part < -100) {
              // A wide backwards kern is how a generator spells a space.
              _space();
            }
          }
        }
        break;
    }
  }

  /// The font to fall back on when a `Tf` names one the resources didn't
  /// wire up — sound only where the document has just the one.
  _FontMap? _soleFont() => fonts.length == 1 ? fonts.values.first : null;

  double? _number(List<Object> operands, int fromEnd) {
    final index = operands.length - 1 - fromEnd;
    if (index < 0) return null;
    final value = operands[index];
    return value is num ? value.toDouble() : null;
  }

  void _move(double x, double y) {
    if ((y - _y).abs() > _lineGap) {
      _break();
    } else if (x - _x > _columnGap) {
      // Text jumped along the same line: a column rule, in the only terms
      // a plain-text schedule has for one.
      _space();
      _space();
    }
    _x = x;
    _y = y;
  }

  void _space() {
    if (_line.isNotEmpty && !_line.toString().endsWith('  ')) _line.write(' ');
  }

  void _break() {
    final line = _line.toString().trimRight();
    if (line.isNotEmpty) _lines.add(line);
    _line.clear();
  }

  void _write(_Str text) {
    final font = _font;
    if (font != null && !font.readable) {
      _dropped += text.bytes.length;
      return;
    }
    if (font == null || font.codes.isEmpty) {
      _line.write(latin1.decode(text.bytes, allowInvalid: true));
      _kept += text.bytes.length;
      return;
    }
    final width = font.bytesPerCode;
    for (var i = 0; i + width <= text.bytes.length; i += width) {
      var code = 0;
      for (var b = 0; b < width; b++) {
        code = (code << 8) | text.bytes[i + b];
      }
      final glyph = font.codes[code];
      if (glyph == null) {
        _dropped++;
      } else {
        _line.write(glyph);
        _kept++;
      }
    }
  }

  String? finish() {
    _break();
    if (_kept == 0 || _dropped > _kept) return null;
    final text = _lines.join('\n');
    return text.trim().isEmpty ? null : text;
  }
}

class _Name {
  const _Name(this.value);
  final String value;
}

class _Operator {
  const _Operator(this.name);
  final String name;
}

class _Str {
  const _Str(this.bytes);
  final List<int> bytes;
}

/// A content stream, token by token. Only as much of the syntax as the text
/// operators need: strings, numbers, names, arrays and operators.
class _Scanner {
  _Scanner(this._source);

  final String _source;
  int _at = 0;

  Object? next() {
    while (_at < _source.length) {
      final char = _source[_at];
      if (char.trim().isEmpty || char == '\x00') {
        _at++;
      } else if (char == '%') {
        while (_at < _source.length && _source[_at] != '\n') {
          _at++;
        }
      } else {
        break;
      }
    }
    if (_at >= _source.length) return null;

    final char = _source[_at];
    if (char == '(') return _literal();
    if (char == '<') {
      if (_at + 1 < _source.length && _source[_at + 1] == '<') {
        _at += 2;
        return const _Operator('<<');
      }
      return _hex();
    }
    if (char == '>') {
      _at += _source.startsWith('>>', _at) ? 2 : 1;
      return const _Operator('>>');
    }
    if (char == '[') return _array();
    if (char == ']') {
      _at++;
      return const _Operator(']');
    }
    if (char == '/') return _name();
    if (RegExp(r'[-+.\d]').hasMatch(char)) return _number();
    return _operator();
  }

  /// `(a string)`, with the escapes and the octal a generator writes for
  /// anything outside ASCII.
  _Str _literal() {
    _at++;
    final bytes = <int>[];
    var depth = 1;
    while (_at < _source.length) {
      final char = _source[_at++];
      if (char == '\\') {
        if (_at >= _source.length) break;
        final escape = _source[_at++];
        const simple = {
          'n': 10, 'r': 13, 't': 9, 'b': 8, 'f': 12, //
          '(': 40, ')': 41, '\\': 92,
        };
        final known = simple[escape];
        if (known != null) {
          bytes.add(known);
        } else if (RegExp(r'[0-7]').hasMatch(escape)) {
          var octal = escape;
          while (octal.length < 3 &&
              _at < _source.length &&
              RegExp(r'[0-7]').hasMatch(_source[_at])) {
            octal += _source[_at++];
          }
          bytes.add(int.parse(octal, radix: 8));
        } else if (escape != '\n') {
          bytes.add(escape.codeUnitAt(0));
        }
      } else if (char == '(') {
        depth++;
        bytes.add(40);
      } else if (char == ')') {
        if (--depth == 0) break;
        bytes.add(41);
      } else {
        bytes.add(char.codeUnitAt(0));
      }
    }
    return _Str(bytes);
  }

  _Str _hex() {
    final end = _source.indexOf('>', _at);
    final digits = _source
        .substring(_at + 1, end == -1 ? _source.length : end)
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    _at = end == -1 ? _source.length : end + 1;
    final bytes = <int>[];
    for (var i = 0; i < digits.length; i += 2) {
      final pair = i + 2 <= digits.length
          ? digits.substring(i, i + 2)
          // An odd number of digits is padded with a zero, says the spec.
          : '${digits[i]}0';
      bytes.add(int.parse(pair, radix: 16));
    }
    return _Str(bytes);
  }

  List<Object> _array() {
    _at++;
    final items = <Object>[];
    while (_at < _source.length) {
      final token = next();
      if (token == null) break;
      if (token is _Operator) {
        if (token.name == ']') break;
        continue;
      }
      if (items.length < 4096) items.add(token);
    }
    return items;
  }

  _Name _name() {
    final match = RegExp(r'^/([^\s/\[\]<>()%]*)').firstMatch(
        _source.substring(_at, (_at + 128).clamp(0, _source.length)));
    final value = match?.group(1) ?? '';
    _at += value.length + 1;
    return _Name(value);
  }

  Object _number() {
    final match = RegExp(r'^[-+]?[\d.]+').firstMatch(
        _source.substring(_at, (_at + 32).clamp(0, _source.length)))!;
    _at += match.group(0)!.length;
    return double.tryParse(match.group(0)!) ?? 0;
  }

  _Operator _operator() {
    final match = RegExp(r"^[A-Za-z*'\x22]+").firstMatch(
        _source.substring(_at, (_at + 32).clamp(0, _source.length)));
    if (match == null) {
      _at++;
      return const _Operator('');
    }
    _at += match.group(0)!.length;
    return _Operator(match.group(0)!);
  }
}
