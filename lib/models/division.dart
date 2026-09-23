import 'throw_event.dart';

/// Who a competition is for: the girls' shot and the boys' shot are two
/// contests on one afternoon, with two fields, two orders and two cuts.
///
/// Not what an implement is filed under — a 4 kg shot is a 4 kg shot
/// whoever throws it, which is why a best stays per weight (see
/// `ImplementSpec`). This is the name a meet calls the competition by, and
/// the word a coach looks for first on a screen with six throws events on
/// it: a program says 'Event 15 Boys Shot Put', not 'Shot Put · 12 lb'.
enum Division {
  // Declared in the order a meet screen lists them within one event.
  girls,
  boys,
  women,
  men;

  /// The word a program heads the event with — 'Girls Shot Put',
  /// "Men's Discus". The school divisions are plural nouns on a U.S. sheet
  /// and the senior ones possessive, and a heading written the other way
  /// round reads as a typo to anybody who has held one.
  String get label => switch (this) {
        Division.girls => 'Girls',
        Division.boys => 'Boys',
        Division.women => "Women's",
        Division.men => "Men's",
      };

  /// The plain word, for a chip that has no event after it.
  String get word => switch (this) {
        Division.girls => 'Girls',
        Division.boys => 'Boys',
        Division.women => 'Women',
        Division.men => 'Men',
      };

  /// What this division throws at [event] when nobody has said — the
  /// weight a heading naming only the division is read at, and the one the
  /// entry dialog moves to when a division is picked.
  double implementKgFor(ThrowEvent event) => defaultImplementKg(event,
      women: this == Division.girls || this == Division.women,
      school: this == Division.girls || this == Division.boys);

  /// Which division a heading names, or null for one that names none — or
  /// names two, as a 'Boys & Girls' combined field does.
  ///
  /// Only the words themselves: a 'U18' or a 'High School' says how heavy
  /// the implement is and nothing about who is throwing it, and the
  /// single-letter 'W' the weight guess accepts is too often a school's
  /// initial to name a competition by.
  static Division? read(String heading) {
    final found = <Division>{
      if (_girls.hasMatch(heading)) Division.girls,
      if (_boys.hasMatch(heading)) Division.boys,
      if (_women.hasMatch(heading)) Division.women,
      if (_men.hasMatch(heading)) Division.men,
    };
    return found.length == 1 ? found.single : null;
  }

  static Division? fromName(String? name) {
    for (final division in Division.values) {
      if (division.name == name) return division;
    }
    return null;
  }
}

final _girls = RegExp(r'\bgirls?\b', caseSensitive: false);
final _boys = RegExp(r'\bboys?\b', caseSensitive: false);
final _women =
    RegExp(r"\b(women|woman|female|ladies)(?:['’]?s)?\b", caseSensitive: false);
// 'Men' and 'Mens' but not the 'men' inside 'Women' — the word boundary
// sees to that.
final _men = RegExp(r"\b(men|man|male)(?:['’]?s)?\b", caseSensitive: false);

/// What a division throws, for a sheet or a coach that didn't say.
///
/// A division is two axes and no more — senior or school, and men or
/// women — so that is all this is handed.
///
/// The school implements are the U.S. high-school ones: the boys' 12 lb shot
/// and 1.6 kg discus, both their own weight rather than a rounded senior
/// shell (see [ImplementSpec]). Girls throw the 4 kg shot and 1 kg discus
/// that are also the senior women's, so only the boys' side needs the split.
/// Javelin is the 800 g for men and boys alike, which is why it doesn't.
double defaultImplementKg(ThrowEvent event,
    {required bool women, required bool school}) {
  switch (event) {
    case ThrowEvent.shotPut:
      if (women) return 4;
      return school ? 5.44 : 7.26;
    case ThrowEvent.discus:
      if (women) return 1;
      return school ? 1.6 : 2;
    case ThrowEvent.hammer:
      // Not a high-school event, so no school weight to guess: senior men's
      // or senior women's is the most a division can say.
      return women ? 4 : 7.26;
    case ThrowEvent.javelin:
      return women ? 0.6 : 0.8;
  }
}
