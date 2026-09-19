import 'meet_board.dart' show boardNameOf;

/// The editable half of an athlete: what a coach fills in about them that
/// no throw carries.
///
/// A profile ([AthleteProfile]) is derived from the throws — it can't be
/// edited, because there is nothing stored to edit. This is the record that
/// sits alongside it: a nickname to show, the name a heat sheet is matched
/// against, and the school it is matched at. It is keyed to the athlete by
/// [name] — the tag every throw and mark of theirs already holds — and
/// never renames that, so retagging a clip can't orphan the record.
class AthleteRecord {
  const AthleteRecord({
    required this.name,
    this.nickname = '',
    this.firstName = '',
    this.lastName = '',
    this.school = '',
  });

  /// The library's spelling of this athlete: the athlete tag their throws
  /// carry, and the key this record is filed under. Changing what to *show*
  /// is [nickname]'s job — this stays the identity so nothing detaches.
  final String name;

  /// What to draw instead of [name] — 'Bud' for a Robert who nobody calls
  /// Robert. Blank means show the name as filed. The throws keep [name];
  /// this only changes the label.
  final String nickname;

  /// The two halves of their name as a meet program prints it.
  ///
  /// Two fields rather than one, because a family name is not something to
  /// be worked out from a string. Everything that shortens a name to what a
  /// board has room for was reading the last word as the surname, which is
  /// right for 'Nnamdi Achebe' and wrong for 'Anna Sofia' — two given names
  /// and no surname at all, drawn across a sector as 'Sofia'. A first name
  /// with a space in it is ordinary in most of the world, and there is no
  /// rule over a string that tells one from the other. So the coach says,
  /// once, and nothing guesses again.
  ///
  /// Both blank when they haven't said, which is when the guess comes back
  /// — knowing nothing, the last word is still the best reading there is.
  final String firstName;
  final String lastName;

  /// Their school or club — the other half of a heat-sheet match, and what
  /// tells two athletes of the same surname apart. Blank when unset.
  final String school;

  /// What to show for this athlete: the nickname when there is one, else the
  /// library spelling.
  String get displayName => nickname.trim().isEmpty ? name : nickname.trim();

  /// Their name as a program would print it, which is what
  /// `heat_sheet_parser.matchAthlete` links an entry against. Blank when
  /// neither half has been filled in.
  String get fullName =>
      [firstName.trim(), lastName.trim()].where((p) => p.isNotEmpty).join(' ');

  /// The name a board has room for: the family name, and the given name
  /// when the coach has said there is no family name to use.
  ///
  /// Blank when the record says nothing about either, which is what sends
  /// the caller back to guessing off the library spelling.
  String get boardName =>
      lastName.trim().isNotEmpty ? lastName.trim() : firstName.trim();

  /// Whether the coach has actually put anything on the record. An empty one
  /// is worth dropping rather than storing, so a name typed into the editor
  /// and cleared again leaves nothing behind.
  bool get isEmpty =>
      nickname.trim().isEmpty &&
      firstName.trim().isEmpty &&
      lastName.trim().isEmpty &&
      school.trim().isEmpty;

  AthleteRecord copyWith({
    String? name,
    String? nickname,
    String? firstName,
    String? lastName,
    String? school,
  }) =>
      AthleteRecord(
        name: name ?? this.name,
        nickname: nickname ?? this.nickname,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        school: school ?? this.school,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (nickname.trim().isNotEmpty) 'nickname': nickname.trim(),
        if (firstName.trim().isNotEmpty) 'firstName': firstName.trim(),
        if (lastName.trim().isNotEmpty) 'lastName': lastName.trim(),
        if (school.trim().isNotEmpty) 'school': school.trim(),
      };

  factory AthleteRecord.fromJson(Map<String, dynamic> json) {
    final first = (json['firstName'] as String?)?.trim() ?? '';
    final last = (json['lastName'] as String?)?.trim() ?? '';
    // A record written before the name had two halves holds one string. It
    // is split the way everything used to read it — the last word is the
    // surname — so nothing moves on the day of the upgrade, and the coach
    // is looking at two fields they can put right for the athletes it was
    // wrong for.
    final held = (json['fullName'] as String?)?.trim() ?? '';
    if (first.isEmpty && last.isEmpty && held.isNotEmpty) {
      final words = held.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
      return AthleteRecord(
        name: (json['name'] as String?)?.trim() ?? '',
        nickname: (json['nickname'] as String?)?.trim() ?? '',
        firstName: words.length > 1 ? words.sublist(0, words.length - 1).join(' ') : '',
        lastName: words.isEmpty ? '' : words.last,
        school: (json['school'] as String?)?.trim() ?? '',
      );
    }
    return AthleteRecord(
      name: (json['name'] as String?)?.trim() ?? '',
      nickname: (json['nickname'] as String?)?.trim() ?? '',
      firstName: first,
      lastName: last,
      school: (json['school'] as String?)?.trim() ?? '',
    );
  }
}

/// The name a board has room for, for an athlete the library may or may not
/// hold a record for.
///
/// [record] is the coach's own answer and wins outright. Without one there
/// is nothing to go on but the spelling the throws carry, and
/// [boardNameOf]'s reading of it — the last word — which is right far more
/// often than it is wrong and is the reason it stood for as long as it did.
String athleteBoardName(String name, AthleteRecord? record) {
  final said = record?.boardName ?? '';
  return said.isNotEmpty ? said : boardNameOf(name);
}
