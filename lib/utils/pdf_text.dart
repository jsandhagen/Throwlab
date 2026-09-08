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
    if (!text.contains('BT') || !_isContent(content)) continue;
    page.run(text);
  }

  return page.finish();
}

/// Whether a stream is page content rather than data that happens to spell
/// `BT`.
///
/// Operators and their operands are written in ASCII, so a content stream
/// holds no control bytes at all; a color profile or an image is a third
/// of the way made of them, and scanning one yields nothing but the
/// occasional two bytes that look like the start of a run of text.
bool _isContent(List<int> bytes) {
  var control = 0;
  for (final byte in bytes) {
    // Tab, newline, form feed and return are the whitespace a generator
    // lays its operators out with; nothing else below a space belongs.
    if ((byte < 0x20 && byte != 9 && byte != 10 && byte != 12 && byte != 13) ||
        byte == 0x7F) {
      control++;
    }
  }
  return control * 20 < bytes.length;
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

/// Half an em, which is about what a character of prose averages and the
/// closest honest guess for a font that never published its widths.
const _unknownAdvance = 0.5;

/// What a font's codes mean, and how wide they are, per font resource name.
class _FontMap {
  _FontMap(this.codes, this.bytesPerCode, this.readable,
      [this.widths = const {}]);

  /// Empty for a font whose codes are its characters, which is most of the
  /// ones that spell out a schedule.
  final Map<int, String> codes;
  final int bytesPerCode;

  /// False for a subset font that never said what its glyphs mean. Its
  /// codes are indexes into a table this can't see, so its text is dropped
  /// rather than emitted as the mojibake it would decode to.
  final bool readable;

  /// How far each code carries the pen along, in ems, out of the font's
  /// own `/Widths`. It is what tells a cell that ended from a column that
  /// started: without it the gap between two runs is unreadable, since
  /// most of it is the width of the words in front of it.
  final Map<int, double> widths;

  double advance(int code) => widths[code] ?? _unknownAdvance;
}

/// A simple font's widths, code by code, in ems.
///
/// A composite font keeps its widths somewhere this doesn't look, and a
/// base font may publish none at all; both fall back to half an em.
Map<int, double> _widths(String font, Map<int, String> objects) {
  final first = RegExp(r'/FirstChar\s+(\d+)').firstMatch(font);
  final firstCode = first == null ? null : int.tryParse(first.group(1)!);
  if (firstCode == null) return const {};
  var array = RegExp(r'/Widths\s*\[([^\]]*)\]').firstMatch(font)?.group(1);
  if (array == null) {
    // Long fonts keep the array in an object of its own.
    final ref = RegExp(r'/Widths\s+(\d+)\s+\d+\s+R').firstMatch(font);
    final body = ref == null ? null : objects[int.tryParse(ref.group(1)!) ?? -1];
    array =
        body == null ? null : RegExp(r'\[([^\]]*)\]').firstMatch(body)?.group(1);
  }
  if (array == null) return const {};

  final widths = <int, double>{};
  var code = firstCode;
  for (final value in RegExp(r'-?[\d.]+').allMatches(array)) {
    widths[code++] = (double.tryParse(value.group(0)!) ?? 0) / 1000;
  }
  return widths;
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
      final widths = _widths(font, objects);
      final toUnicode =
          RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(font);
      if (toUnicode == null) {
        // A simple font with no table is its own encoding: byte in,
        // character out. A composite one without a table is unreadable.
        maps[name] = _FontMap(const {}, 1, !font.contains('/Type0'), widths);
        continue;
      }
      final stream = objects[int.parse(toUnicode.group(1)!)];
      final cmap = stream == null ? null : _streamOf(stream);
      if (cmap == null) {
        maps[name] = _FontMap(const {}, 1, !font.contains('/Type0'), widths);
        continue;
      }
      maps[name] = _parseCMap(latin1.decode(cmap, allowInvalid: true), widths);
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
_FontMap _parseCMap(String cmap, Map<int, double> widths) {
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

  return _FontMap(codes, width == 0 ? 2 : width, true, widths);
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
/// how far along one has to jump to be a column over, and how wide a gap
/// between two runs is a space rather than a kern. All as a fraction of
/// the type's own size: a schedule set in 8pt rules its columns closer
/// together than one set in 12, and only the type says which this is.
const _lineGap = 0.3;
const _columnGap = 0.9;
const _wordGap = 0.2;

/// The page being built up, an operator at a time.
class _Page {
  _Page(this.fonts);

  final Map<String, _FontMap> fonts;
  final StringBuffer _line = StringBuffer();
  final List<String> _lines = [];

  _FontMap? _font;

  /// The pen: where the next glyph lands, moved along by every glyph
  /// written.
  double _x = 0;
  double _y = 0;

  /// The start of the run of text, which `Td` and `T*` step from.
  double _lineX = 0;
  double _lineY = 0;

  /// Where the last glyph left off, which is what says whether the next
  /// one is beside it, a column over, or on the line below. A page that
  /// has had nothing written on it yet has nowhere to measure from.
  double _lastX = 0;
  double _lastY = 0;
  bool _written = false;

  double _size = 0;
  double _scale = 1;
  double _leading = 0;
  int _kept = 0;

  /// Characters thrown away because the font that spelled them never said
  /// what they meant. A page that is mostly this is not text.
  int _dropped = 0;

  /// The type's size where the text is being laid down, which every gap is
  /// measured against. `Tf` gives it in text space and `Tm` scales that up,
  /// so a generator is free to set 12pt type as one unit blown up
  /// seventy-five times, and plenty do.
  double get _em {
    final em = _size * _scale;
    return em > 0 ? em : 12;
  }

  void run(String content) {
    // Each stream is a page, near enough: what is at the top of the next
    // one does not carry on from the bottom of this one.
    _break();
    _written = false;

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
        // A generator is free to open a run of text for every cell of a
        // table, so `BT` and `ET` say nothing about where the words are:
        // the line is decided by where the next ones land.
        _place(0, 0);
        break;
      case 'Tf':
        final name =
            operands.length >= 2 ? operands[operands.length - 2] : null;
        if (name is _Name) _font = fonts[name.value] ?? _soleFont();
        _size = _number(operands, 0) ?? _size;
        break;
      case 'TL':
        _leading = _number(operands, 0) ?? _leading;
        break;
      case 'Td':
      case 'TD':
        final ty = _number(operands, 0) ?? 0;
        final tx = _number(operands, 1) ?? 0;
        if (op == 'TD') _leading = -ty;
        _place(_lineX + tx * _scale, _lineY + ty * _scale);
        break;
      case 'Tm':
        // The first column of the matrix is how big the type is drawn; a
        // page turned on its side carries it in the second.
        final a = (_number(operands, 5) ?? 1).abs();
        final b = (_number(operands, 4) ?? 0).abs();
        _scale = a > 0 ? a : (b > 0 ? b : 1);
        _place(_number(operands, 1) ?? 0, _number(operands, 0) ?? 0);
        break;
      case 'T*':
        _place(_lineX, _lineY - _leading * _scale);
        break;
      case 'Tj':
      case '\'':
      case '"':
        if (op != 'Tj') _place(_lineX, _lineY - _leading * _scale);
        final text = operands.isEmpty ? null : operands.last;
        if (text is _Str) _write(text);
        break;
      case 'TJ':
        final array = operands.isEmpty ? null : operands.last;
        if (array is List<Object>) {
          for (final part in array) {
            if (part is _Str) {
              _write(part);
            } else if (part is num) {
              // A kern, in thousandths of an em and backwards. A wide one
              // is how a generator spells a space, which the gap between
              // this run and the next then reads as one.
              _x -= part / 1000 * _em;
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

  /// Start a run of text at (x, y), with the pen at its head.
  void _place(double x, double y) {
    _lineX = x;
    _lineY = y;
    _x = x;
    _y = y;
  }

  /// The line break, column rule or space that the gap between the last
  /// glyph and the pen calls for.
  void _separate() {
    if (!_written) return;
    final em = _em;
    if ((_y - _lastY).abs() > _lineGap * em) {
      _break();
    } else if (_x - _lastX > _columnGap * em) {
      // Text jumped along the same line: a column rule, in the only terms
      // a plain-text schedule has for one.
      _space();
      _space();
    } else if (_x - _lastX > _wordGap * em) {
      _space();
    }
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
    // A font whose codes are its characters is read a byte at a time; one
    // that ships a table says how wide its codes are.
    final plain = font == null || font.codes.isEmpty;
    final width = plain ? 1 : font.bytesPerCode;

    final glyphs = StringBuffer();
    var advance = 0.0;
    var kept = 0;
    var dropped = 0;
    for (var i = 0; i + width <= text.bytes.length; i += width) {
      var code = 0;
      for (var b = 0; b < width; b++) {
        code = (code << 8) | text.bytes[i + b];
      }
      advance += font?.advance(code) ?? _unknownAdvance;
      final glyph = plain ? String.fromCharCode(code) : font.codes[code];
      if (glyph == null) {
        dropped++;
      } else {
        glyphs.write(glyph);
        kept++;
      }
    }

    if (kept > 0) {
      _separate();
      _line.write(glyphs);
    }
    _kept += kept;
    _dropped += dropped;
    // The pen ends up past what was just written, which is where the gap
    // to whatever comes next is measured from.
    _x += advance * _em;
    if (kept > 0) {
      _lastX = _x;
      _lastY = _y;
      _written = true;
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
        _source.substring(_at, (_at + 32).clamp(0, _source.length)));
    if (match == null) {
      // A sign with nothing behind it. Not a number, and not a reason to
      // give up on the page: step over it the way an unknown operator is
      // stepped over.
      _at++;
      return 0;
    }
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
