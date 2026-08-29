import 'package:intl/intl.dart';

/// Money on this platform is stored in kobo — the minor unit — everywhere, and
/// every amount this app sends or receives is a whole number of them. The screens
/// are the only place a major-unit figure exists, so the conversion lives here and
/// nowhere else.
class Money {
  Money._();

  static const int minorPerMajor = 100;

  static final NumberFormat _major = NumberFormat('#,##0.00', 'en_NG');
  static final NumberFormat _plain = NumberFormat('#,##0', 'en_NG');

  /// `123456` → `₦1,234.56`.
  static String format(int minor) => '₦${_major.format(minor / minorPerMajor)}';

  /// `123400` → `₦1,234` — used where the kobo are always zero and the noise
  /// costs more than the precision buys.
  static String formatWhole(int minor) {
    if (minor % minorPerMajor != 0) return format(minor);
    return '₦${_plain.format(minor ~/ minorPerMajor)}';
  }

  /// Reads what the collector typed into the field. Grouping separators and a
  /// stray currency symbol are accepted because the input formatter puts them
  /// there; anything else returns null so the field can say so.
  static int? parseToMinor(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value < 0) return null;
    return (value * minorPerMajor).round();
  }
}

/// Dates the way a receipt reads them.
class Dates {
  Dates._();

  static final DateFormat _day = DateFormat('d MMM yyyy');
  static final DateFormat _dayTime = DateFormat('d MMM yyyy, h:mm a');

  static String day(DateTime? value) =>
      value == null ? '—' : _day.format(value.toLocal());

  static String dayTime(DateTime? value) =>
      value == null ? '—' : _dayTime.format(value.toLocal());

  static DateTime? tryParse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
