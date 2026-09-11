import 'dart:convert';
import 'dart:typed_data';

/// Writes a small PDF: pages of fixed-width text, with rules between them.
///
/// Deliberately narrow, the way [pdfText] is deliberately narrow at the
/// other end. A results sheet needs one family, three weights of it, lines
/// and a page break; a general-purpose PDF library is a dependency the size
/// of the rest of the app for a file nobody will open twice.
///
/// Everything is set in Courier, which is not a nostalgic choice: a results
/// sheet is columns, and a fixed-width face is the only way to line them up
/// without carrying a table of glyph widths around. It is also what every
/// meet program in the world is printed in. One consequence worth knowing:
/// a line is measured by counting characters, so [columnsAt] is exact.
///
/// The streams are left uncompressed. A meet's results are a few kilobytes
/// of text, and an uncompressed file is one anybody — this app's own reader
/// included — can open without an inflater.
class PdfSheet {
  PdfSheet({
    this.width = 612,
    this.height = 792,
    this.margin = 46,
    this.leading = 12,
    this.footer = '',
  }) {
    _newPage();
  }

  /// US Letter by default, in points. A results sheet is printed and pinned
  /// to a board as often as it is read on a phone.
  final double width;
  final double height;
  final double margin;

  /// Points between one line's baseline and the next.
  final double leading;

  /// Set across the bottom of every page, with the page number after it.
  final String footer;

  /// Every glyph in Courier is this wide, as a fraction of the type size.
  static const _advance = 0.6;

  final List<StringBuffer> _pages = [];
  late StringBuffer _page;
  late double _y;

  /// How many characters of [size] fit between the margins. What a report
  /// lays its columns out against.
  int columnsAt(double size) =>
      ((width - margin * 2) / (size * _advance)).floor();

  /// Writes one line and moves down. [spacing] overrides the leading for
  /// the step *after* this line, which is how a heading gets air under it
  /// without a blank line's worth.
  void line(
    String text, {
    double size = 9,
    PdfFace face = PdfFace.regular,
    double indent = 0,
    double? spacing,
  }) {
    _room(size);
    if (text.isNotEmpty) {
      _page.write('BT /${face.resource} ${_n(size)} Tf 1 0 0 1 '
          '${_n(margin + indent)} ${_n(_y)} Tm (${_escape(text)}) Tj ET\n');
    }
    _y -= spacing ?? leading;
  }

  /// One line built out of runs, each starting at a character column.
  ///
  /// Every glyph in Courier is the same width, so a column is an exact
  /// position rather than a measurement — which is what lets one row of a
  /// table carry two faces without the columns under it moving. The
  /// winning throw of a series is set in bold where it sits in the series,
  /// and nothing else on the line shifts by a hair.
  void columns(
    List<PdfRun> runs, {
    double size = 9,
    double? spacing,
  }) {
    _room(size);
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      _page.write('BT /${run.face.resource} ${_n(size)} Tf 1 0 0 1 '
          '${_n(margin + run.column * size * _advance)} ${_n(_y)} Tm '
          '(${_escape(run.text)}) Tj ET\n');
    }
    _y -= spacing ?? leading;
  }

  /// Sets aside a box [height] points tall and hands it to [draw].
  ///
  /// Drawing is worth having on a results sheet — a competition has a
  /// shape, and a column of numbers is the one way of showing it that
  /// hides it — but nothing outside this file should have to know what a
  /// PDF operator looks like. So the box comes with its own coordinates,
  /// measured in points from its bottom-left corner, and the sheet keeps
  /// track of where on the page it actually landed.
  void figure(double height, void Function(PdfFigure into) draw,
      {double below = 4}) {
    _room(height + below);
    _y -= height;
    draw(PdfFigure._(_page, margin, _y, width - margin * 2, height));
    _y -= below;
  }

  /// Breaks the page unless [points] of it are left, so a heading is never
  /// stranded at the foot of one with its table over the leaf.
  void reserve(double points) => _room(points);

  /// A rule across the text column, with a little air either side of it.
  void rule({double thickness = 0.5, double above = 4, double below = 8}) {
    _room(above + below);
    _y -= above;
    _page.write('q ${_n(thickness)} w ${_n(margin)} ${_n(_y)} m '
        '${_n(width - margin)} ${_n(_y)} l S Q\n');
    _y -= below;
  }

  void gap([double points = 6]) => _y -= points;

  /// Starts the next page, unless this one is still blank — a report that
  /// breaks before each section should not open on an empty sheet.
  void pageBreak() {
    if (_page.isEmpty) return;
    _newPage();
  }

  /// The finished file.
  Uint8List save() {
    _stampFooters();
    final buffer = BytesBuilder();
    final offsets = <int, int>{};
    void write(String text) => buffer.add(latin1.encode(text));
    void object(int id, String body) {
      offsets[id] = buffer.length;
      write('$id 0 obj\n$body\nendobj\n');
    }

    write('%PDF-1.4\n');
    final pageIds = [for (var i = 0; i < _pages.length; i++) 3 + i * 2];
    final fontBase = 3 + _pages.length * 2;

    object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    object(
        2,
        '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
        '/Count ${_pages.length} >>');

    for (var i = 0; i < _pages.length; i++) {
      final contentId = pageIds[i] + 1;
      object(
          pageIds[i],
          '<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 ${_n(width)} ${_n(height)}] '
          '/Resources << /Font << '
          '${[
            for (var f = 0; f < PdfFace.values.length; f++)
              '/${PdfFace.values[f].resource} ${fontBase + f} 0 R'
          ].join(' ')} >> >> '
          '/Contents $contentId 0 R >>');
      final stream = _pages[i].toString();
      offsets[contentId] = buffer.length;
      write('$contentId 0 obj\n<< /Length ${stream.length} >>\nstream\n');
      write(stream);
      write('\nendstream\nendobj\n');
    }

    for (var f = 0; f < PdfFace.values.length; f++) {
      object(
          fontBase + f,
          '<< /Type /Font /Subtype /Type1 '
          '/BaseFont /${PdfFace.values[f].baseFont} '
          '/Encoding /WinAnsiEncoding >>');
    }

    // The cross-reference table: one twenty-byte row per object, in order,
    // and the free head that every PDF starts its table with.
    final count = fontBase + PdfFace.values.length;
    final start = buffer.length;
    write('xref\n0 $count\n0000000000 65535 f \n');
    for (var id = 1; id < count; id++) {
      write('${offsets[id]!.toString().padLeft(10, '0')} 00000 n \n');
    }
    write('trailer\n<< /Size $count /Root 1 0 R >>\n'
        'startxref\n$start\n%%EOF\n');
    return buffer.toBytes();
  }

  void _newPage() {
    _page = StringBuffer();
    _pages.add(_page);
    _y = height - margin;
  }

  /// Breaks the page when [needed] points would run off the bottom of it.
  /// The footer's line is kept clear, so a table can never run into it.
  void _room(double needed) {
    if (_y - needed < margin + (footer.isEmpty ? 0 : leading * 2)) {
      _newPage();
    }
  }

  /// Stamps the footer on every page. Done at the end because a page has to
  /// know how many others there are before it can say which one it is.
  void _stampFooters() {
    if (footer.isEmpty) return;
    for (var i = 0; i < _pages.length; i++) {
      final text = _pages.length == 1
          ? footer
          : '$footer  ·  page ${i + 1} of ${_pages.length}';
      _pages[i].write('BT /${PdfFace.oblique.resource} 8 Tf 1 0 0 1 '
          '${_n(margin)} ${_n(margin - 12)} Tm (${_escape(text)}) Tj ET\n');
    }
  }

  /// Trims a number to something a PDF reader will not choke on and a human
  /// can diff.
  static String _n(double value) {
    final rounded = (value * 100).round() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toString();
  }

  /// A string as a PDF literal. Parentheses and backslashes are the
  /// document's own punctuation and have to be escaped; anything past
  /// Latin-1 has no code in this encoding at all, so the handful of
  /// typographic characters the app actually uses are folded to the ASCII
  /// they stand for rather than dropped.
  static String _escape(String text) {
    final folded = text
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('−', '-')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('…', '...');
    final out = StringBuffer();
    for (final rune in folded.runes) {
      final char = String.fromCharCode(rune);
      if (char == '(' || char == ')' || char == r'\') {
        out.write('\\$char');
      } else if (rune < 0x20 || rune > 0xFF) {
        out.write('?');
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }
}

/// A run of text starting at a character column of a [PdfSheet.columns]
/// row. See that for why a column is a count rather than a measurement.
class PdfRun {
  const PdfRun(this.text, this.column, [this.face = PdfFace.regular]);

  final String text;
  final int column;
  final PdfFace face;
}

/// A box on the page to draw in, with its own coordinates: points right
/// from its left edge, and points up from its bottom.
///
/// Deliberately four operations wide. A results sheet needs rules, ticks,
/// a filled bar and a word beside them — a drawing API any larger would be
/// a chart library, which is the dependency this whole file exists to
/// avoid.
class PdfFigure {
  PdfFigure._(this._page, this._left, this._bottom, this.width, this.height);

  final StringBuffer _page;
  final double _left;
  final double _bottom;

  final double width;
  final double height;

  /// A straight line. [dash] is the on/off pattern in points, for the kind
  /// of line that means 'this is where something falls' rather than 'this
  /// is a thing' — the cut, mostly.
  void line(
    double x1,
    double y1,
    double x2,
    double y2, {
    double thickness = 0.5,
    double gray = 0,
    List<double>? dash,
  }) {
    _page.write('q ${PdfSheet._n(gray)} G ${PdfSheet._n(thickness)} w ');
    if (dash != null) {
      _page.write('[${dash.map(PdfSheet._n).join(' ')}] 0 d ');
    }
    _page.write('${PdfSheet._n(_left + x1)} ${PdfSheet._n(_bottom + y1)} m '
        '${PdfSheet._n(_left + x2)} ${PdfSheet._n(_bottom + y2)} l S Q\n');
  }

  /// A filled rectangle.
  void fill(double x, double y, double w, double h, {double gray = 0}) {
    if (w <= 0 || h <= 0) return;
    _page.write('q ${PdfSheet._n(gray)} g ${PdfSheet._n(_left + x)} '
        '${PdfSheet._n(_bottom + y)} ${PdfSheet._n(w)} ${PdfSheet._n(h)} '
        're f Q\n');
  }

  /// A word in the box. [y] is its baseline; [align] says which edge of it
  /// [x] is.
  void text(
    String text, {
    required double x,
    required double y,
    double size = 7,
    PdfFace face = PdfFace.regular,
    PdfAlign align = PdfAlign.left,
    double gray = 0,
  }) {
    if (text.isEmpty) return;
    final wide = text.length * size * PdfSheet._advance;
    final at = switch (align) {
      PdfAlign.left => x,
      PdfAlign.right => x - wide,
      PdfAlign.center => x - wide / 2,
    };
    _page.write('q ${PdfSheet._n(gray)} g BT /${face.resource} '
        '${PdfSheet._n(size)} Tf 1 0 0 1 ${PdfSheet._n(_left + at)} '
        '${PdfSheet._n(_bottom + y)} Tm (${PdfSheet._escape(text)}) Tj ET Q\n');
  }
}

/// Which edge of a word in a [PdfFigure] its x is.
enum PdfAlign { left, right, center }

/// The three faces of Courier a sheet is set in.
enum PdfFace {
  regular('F1', 'Courier'),
  bold('F2', 'Courier-Bold'),
  oblique('F3', 'Courier-Oblique');

  const PdfFace(this.resource, this.baseFont);

  /// What the page's resource dictionary calls it.
  final String resource;

  /// One of the fourteen faces every reader is required to have, so nothing
  /// has to be embedded.
  final String baseFont;
}
