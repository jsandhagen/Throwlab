/// What the day was like.
///
/// A javelin series thrown into a headwind is a different competition from
/// the same series with the wind behind it, and a coach reading a season
/// back six months later has no way to tell unless somebody wrote it down
/// while they were standing in it. So a meet carries the weather.
///
/// It hangs off the meet rather than off each throw because the weather is
/// the day's, not the attempt's — and because a coach will fill it in once
/// between flights, which is the difference between it being recorded and
/// not being recorded at all.
library;

/// What the sky was doing. Deliberately short: these are the words a coach
/// would actually write on a results sheet, not a forecast.
enum MeetSky {
  unknown('', ''),
  clear('Clear', '☀'),
  cloudy('Cloudy', '⛅'),
  overcast('Overcast', '☁'),
  rain('Rain', '🌧'),
  snow('Snow', '🌨');

  const MeetSky(this.label, this.glyph);

  final String label;

  /// A single character for a row too narrow for the word.
  final String glyph;
}

/// The wind, as it hit the sector.
///
/// Named for what it does to the throw rather than by a compass point: a
/// coach standing behind the circle knows whether it is into them or behind
/// them, and nobody at a track knows they are facing 240°. A meet where the
/// discus and the javelin faced different ways is what the note is for.
enum MeetWind {
  unknown(''),
  still('Still'),
  head('Headwind'),
  tail('Tailwind'),
  cross('Crosswind');

  const MeetWind(this.label);

  final String label;
}

/// Which scale a temperature was written down in.
enum TemperatureUnit {
  fahrenheit('°F'),
  celsius('°C');

  const TemperatureUnit(this.symbol);

  final String symbol;
}

/// The conditions one meet was thrown in.
///
/// Unlike a distance, the temperature is stored in the unit it was entered
/// in rather than converted to a canonical one. Nothing computes with it —
/// it is read back, and that is all — so converting would only round a
/// number a coach typed exactly.
class MeetConditions {
  const MeetConditions({
    this.sky = MeetSky.unknown,
    this.temperature,
    this.temperatureUnit = TemperatureUnit.fahrenheit,
    this.wind = MeetWind.unknown,
    this.note = '',
  });

  final MeetSky sky;

  /// The temperature as written, in [temperatureUnit]. Null for a meet
  /// nobody said, which is most of them.
  final double? temperature;
  final TemperatureUnit temperatureUnit;

  final MeetWind wind;

  /// Anything the fields above have no room for: 'wet ring', 'delayed an
  /// hour for lightning', 'gusting hard down the runway'.
  final String note;

  /// Nothing was filled in — the usual state of a meet, and the reason
  /// nothing is drawn for one.
  bool get isEmpty =>
      sky == MeetSky.unknown &&
      temperature == null &&
      wind == MeetWind.unknown &&
      note.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// '68°F', or empty when nobody took one. Whole degrees: a track has a
  /// thermometer on a wall, not a laboratory.
  String get temperatureLabel => temperature == null
      ? ''
      : '${temperature!.round()}${temperatureUnit.symbol}';

  /// The line a screen puts under a meet's name: 'Cloudy · 54°F ·
  /// Headwind'. The note is left out — it is a sentence, and this is a
  /// subtitle.
  String get summary => [
        if (sky != MeetSky.unknown) sky.label,
        if (temperature != null) temperatureLabel,
        if (wind != MeetWind.unknown) wind.label,
      ].join(' · ');

  MeetConditions copyWith({
    MeetSky? sky,
    double? temperature,
    bool clearTemperature = false,
    TemperatureUnit? temperatureUnit,
    MeetWind? wind,
    String? note,
  }) =>
      MeetConditions(
        sky: sky ?? this.sky,
        temperature:
            clearTemperature ? null : (temperature ?? this.temperature),
        temperatureUnit: temperatureUnit ?? this.temperatureUnit,
        wind: wind ?? this.wind,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        if (sky != MeetSky.unknown) 'sky': sky.name,
        if (temperature != null) 'temperature': temperature,
        if (temperature != null) 'temperatureUnit': temperatureUnit.name,
        if (wind != MeetWind.unknown) 'wind': wind.name,
        if (note.isNotEmpty) 'note': note,
      };

  factory MeetConditions.fromJson(Map<String, dynamic> json) => MeetConditions(
        sky: MeetSky.values.asNameMap()[json['sky'] as String? ?? ''] ??
            MeetSky.unknown,
        temperature: (json['temperature'] as num?)?.toDouble(),
        temperatureUnit: TemperatureUnit.values
                .asNameMap()[json['temperatureUnit'] as String? ?? ''] ??
            TemperatureUnit.fahrenheit,
        wind: MeetWind.values.asNameMap()[json['wind'] as String? ?? ''] ??
            MeetWind.unknown,
        note: json['note'] as String? ?? '',
      );
}
