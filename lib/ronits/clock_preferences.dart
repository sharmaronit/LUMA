bool validClockSize(String value) =>
    ['small', 'medium', 'large'].contains(value) ||
    (int.tryParse(value) != null &&
        int.parse(value) >= 0 &&
        int.parse(value) <= 100);

String normaliseClockSize(String? value) =>
    value != null && validClockSize(value) ? value : 'medium';

double clockSizePosition(String value) => switch (value) {
  'small' => 0,
  'large' => 100,
  'medium' => 50,
  _ => (double.tryParse(value) ?? 50).clamp(0.0, 100.0),
};

double clockDigitalExtent(String size) =>
    14 + 30 * clockSizePosition(size) / 100;
double clockAnalogExtent(String size) =>
    24 + 136 * clockSizePosition(size) / 100;
