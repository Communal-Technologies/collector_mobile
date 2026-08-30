import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Codepoint ranges no icon may live in, over the range iconsax actually uses
/// (its glyphs run 0x0000–0x0665 and 0xE000–0xFFFE).
///
/// Iconsax packs its filled variants into low codepoints, and a good number of
/// them land on combining marks, format characters and controls. A shaper gives a
/// combining mark no advance and offsets it by an em — U+033A, iconsax's filled
/// bank, paints a whole icon's width to the left of where an `Icon` places it,
/// which is what made the selected Remit tab jump. Nothing renders a control or a
/// format character at all. So the check is on the codepoint, not on the glyph:
/// the outlines are fine, it is the character the font hangs them on that is not.
const _forbidden = <List<int>>[
  [0x0000, 0x0020], // controls and space
  [0x007F, 0x00A0], // controls and no-break space
  [0x00AD, 0x00AD], // soft hyphen
  [0x0300, 0x036F], // combining diacritical marks
  [0x0483, 0x0489],
  [0x0591, 0x05BD],
  [0x05BF, 0x05BF],
  [0x05C1, 0x05C2],
  [0x05C4, 0x05C5],
  [0x05C7, 0x05C7],
  [0x0600, 0x0605], // Arabic format characters
  [0x0610, 0x061A],
  [0x061C, 0x061C],
  [0x064B, 0x065F],
  [0x0670, 0x0670],
  [0x06D6, 0x06DD],
  [0x06DF, 0x06E4],
  [0x06E7, 0x06E8],
  [0x06EA, 0x06ED],
  [0xFE00, 0xFE0F], // variation selectors
  [0xFE20, 0xFE2F], // combining half marks
  [0xFEFF, 0xFEFF], // zero width no-break space
  [0xFFF9, 0xFFFB], // interlinear annotation
];

bool _isForbidden(int codepoint) =>
    _forbidden.any((range) => codepoint >= range[0] && codepoint <= range[1]);

File _iconsaxSource() {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final package = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => entry['name'] == 'iconsax');
  var root = package['rootUri'] as String;
  if (!root.endsWith('/')) root = '$root/';
  return File.fromUri(Uri.parse(root).resolve('lib/iconsax.dart'));
}

void main() {
  test('no icon the app uses is a combining mark or a control character', () {
    final declarations = RegExp(
      r'(\w+)\s*=\s*(?:const\s+)?IconData\(\s*(0x[0-9a-fA-F]+)',
    );
    final codepoints = <String, int>{};
    for (final match in declarations.allMatches(
      _iconsaxSource().readAsStringSync(),
    )) {
      codepoints[match.group(1)!] = int.parse(match.group(2)!);
    }
    expect(codepoints, isNotEmpty, reason: 'iconsax.dart parsed to nothing');

    final usage = RegExp(r'Iconsax\.(\w+)');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in usage.allMatches(source)) {
        final name = match.group(1)!;
        final codepoint = codepoints[name];
        if (codepoint == null || !_isForbidden(codepoint)) continue;
        final line = source.substring(0, match.start).split('\n').length;
        offenders.add(
          '${entity.path}:$line Iconsax.$name is '
          'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these icons will not paint where they are placed:\n'
          '${offenders.join('\n')}',
    );
  });
}
