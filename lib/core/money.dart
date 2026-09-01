import 'package:intl/intl.dart';

/// Which side of the figure a currency symbol sits on.
enum CurrencySymbolPosition { left, right }

/// Reads a cooperative's `currency_symbol_position` setting. Anything other than
/// an explicit `right` is left, which is what most currencies want.
CurrencySymbolPosition currencySymbolPositionFrom(String? raw) =>
    (raw ?? '').trim().toLowerCase() == 'right'
        ? CurrencySymbolPosition.right
        : CurrencySymbolPosition.left;

/// Symbol an ISO 4217 code implies, for a cooperative that named a currency and
/// never chose a symbol. The services fill this in themselves, so it is only a
/// backstop for a grant saved by an older build of this app.
String currencySymbolForCode(String code) {
  final upper = code.trim().toUpperCase();
  if (upper.isEmpty) return '₦';
  try {
    return NumberFormat.simpleCurrency(name: upper).currencySymbol;
  } catch (_) {
    return upper;
  }
}

/// How the cooperative behind the current grant writes its money: the currency,
/// the symbol it prints and the side that symbol goes on.
///
/// It belongs to the grant, not to the app. A person who collects for two
/// cooperatives that chose different currencies must read each one's figures in
/// its own, so switching grants changes this.
class CurrencyDisplay {
  const CurrencyDisplay({
    required this.code,
    required this.symbol,
    this.position = CurrencySymbolPosition.left,
  });

  static const CurrencyDisplay naira =
      CurrencyDisplay(code: 'NGN', symbol: '₦');

  final String code;
  final String symbol;
  final CurrencySymbolPosition position;

  /// The symbol on its own, never empty — what an input adornment or a column
  /// header shows where there is no figure beside it yet.
  String get printableSymbol =>
      symbol.trim().isEmpty ? currencySymbolForCode(code) : symbol.trim();

  /// Puts the symbol on the chosen side. A symbol spelt in letters ("KSh",
  /// "CHF") gets a space so it does not read as part of the number; a glyph does
  /// not.
  String adorn(String figure) {
    final sym = printableSymbol;
    final gap = RegExp(r'^[A-Za-z]+$').hasMatch(sym) ? ' ' : '';
    return position == CurrencySymbolPosition.right
        ? '$figure$gap$sym'
        : '$sym$gap$figure';
  }
}

/// The display the whole app formats with, because most figures are written deep
/// inside the models and the widgets — a receipt line, a float balance, a
/// commission label — where the session is not in scope.
///
/// [SessionCubit] writes it whenever the acting grant changes, and it falls back
/// to naira until a collector has signed in.
class ActiveCurrency {
  CurrencyDisplay _display = CurrencyDisplay.naira;

  CurrencyDisplay get display => _display;

  void set(CurrencyDisplay display) => _display = display;

  void reset() => _display = CurrencyDisplay.naira;
}

final ActiveCurrency activeCurrency = ActiveCurrency();

/// Money on this platform is stored in kobo — the minor unit — everywhere, and
/// every amount this app sends or receives is a whole number of them. The screens
/// are the only place a major-unit figure exists, so the conversion lives here and
/// nowhere else.
class Money {
  Money._();

  static const int minorPerMajor = 100;

  static final NumberFormat _major = NumberFormat('#,##0.00', 'en_NG');
  static final NumberFormat _plain = NumberFormat('#,##0', 'en_NG');

  /// `123456` → `₦1,234.56`, written the way the cooperative asked — its own
  /// symbol, on the side it chose ("1,234.56 CHF"). Pass [display] where the
  /// figure belongs to a grant other than the acting one.
  static String format(int minor, {CurrencyDisplay? display}) =>
      (display ?? activeCurrency.display)
          .adorn(_major.format(minor / minorPerMajor));

  /// `123400` → `₦1,234` — used where the kobo are always zero and the noise
  /// costs more than the precision buys.
  static String formatWhole(int minor, {CurrencyDisplay? display}) {
    if (minor % minorPerMajor != 0) return format(minor, display: display);
    return (display ?? activeCurrency.display)
        .adorn(_plain.format(minor ~/ minorPerMajor));
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
