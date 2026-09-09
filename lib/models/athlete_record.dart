/// The editable half of an athlete: what a coach fills in about them that
/// no throw carries.
///
/// A profile ([AthleteProfile]) is derived from the throws — it can't be
/// edited, because there is nothing stored to edit. This is the record that
/// sits alongside it: a nickname to show, and the full name and school a
/// heat sheet is matched against. It is keyed to the athlete by [name] — the
/// tag every throw and mark of theirs already holds — and never renames
/// that, so retagging a clip can't orphan the record.
class AthleteRecord {
  const AthleteRecord({
    required this.name,
    this.nickname = '',
    this.fullName = '',
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

  /// Their name as a meet program prints it in full, so an athlete the
  /// library knows by a nickname a sheet would never use is still found on
  /// one. Blank when the coach hasn't said.
  final String fullName;

  /// Their school or club — the other half of a heat-sheet match, and what
  /// tells two athletes of the same surname apart. Blank when unset.
  final String school;

  /// What to show for this athlete: the nickname when there is one, else the
  /// library spelling.
  String get displayName => nickname.trim().isEmpty ? name : nickname.trim();

  /// Whether the coach has actually put anything on the record. An empty one
  /// is worth dropping rather than storing, so a name typed into the editor
  /// and cleared again leaves nothing behind.
  bool get isEmpty =>
      nickname.trim().isEmpty &&
      fullName.trim().isEmpty &&
      school.trim().isEmpty;

  AthleteRecord copyWith({
    String? name,
    String? nickname,
    String? fullName,
    String? school,
  }) =>
      AthleteRecord(
        name: name ?? this.name,
        nickname: nickname ?? this.nickname,
        fullName: fullName ?? this.fullName,
        school: school ?? this.school,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (nickname.trim().isNotEmpty) 'nickname': nickname.trim(),
        if (fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
        if (school.trim().isNotEmpty) 'school': school.trim(),
      };

  factory AthleteRecord.fromJson(Map<String, dynamic> json) => AthleteRecord(
        name: (json['name'] as String?)?.trim() ?? '',
        nickname: (json['nickname'] as String?)?.trim() ?? '',
        fullName: (json['fullName'] as String?)?.trim() ?? '',
        school: (json['school'] as String?)?.trim() ?? '',
      );
}
