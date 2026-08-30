import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../state/connectivity_cubit.dart';

/// A titled white panel. Every screen in the app is a stack of these.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// A figure with its label. The label comes first and small, because the number is
/// what the collector is looking for.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = AppColors.ink,
    this.hint,
  });

  final String label;
  final String value;
  final Color tone;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

/// A status in a word, coloured the way the platform colours statuses.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    late Color background;
    late Color foreground;
    switch (status) {
      case 'posted':
      case 'completed':
      case 'active':
      case 'paid':
        background = AppColors.successSoft;
        foreground = AppColors.success;
        break;
      case 'declined':
      case 'failed':
      case 'revoked':
        background = AppColors.dangerSoft;
        foreground = AppColors.danger;
        break;
      case 'unsent':
      case 'pending':
      case 'processing':
      case 'claimed':
      case 'suspended':
      default:
        background = AppColors.warningSoft;
        foreground = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a screen shows when there is nothing to show — with the reason, never just
/// blank space.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 72,
              width: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A coloured notice. Used for the things a collector must not miss: a cash limit
/// they are close to, a receipt the cooperative refused, a suspension.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.text,
    this.tone = AppColors.warning,
    this.background = AppColors.warningSoft,
    this.icon = Iconsax.info_circle,
  });

  final String text;
  final Color tone;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: tone, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the button of an action that cannot be queued — signing in, the code
/// at verify, declaring a remittance. Recording a collection never carries one: that
/// goes to the outbox, so it works with no signal at all.
///
/// It appears only while the app knows the platform is unreachable, and tapping it
/// checks again rather than making the collector wait out the 15-second cycle.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({super.key, required this.reason});

  /// Why this particular action needs the connection, in the collector's terms.
  final String reason;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityCubit, ConnectivityState>(
      builder: (context, network) {
        if (!network.isOffline) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.read<ConnectivityCubit>().recheck(),
            child: Notice(
              text: network.checking
                  ? 'Checking for a connection…'
                  : '$reason Tap here to check again.',
              icon: network.hasTransport
                  ? Iconsax.cloud_cross
                  : Iconsax.wifi_square,
            ),
          ),
        );
      },
    );
  }
}

/// True when the app knows the platform cannot be reached, for the screens that must
/// hold an action back until it can.
bool isOffline(BuildContext context) =>
    context.watch<ConnectivityCubit>().state.isOffline;

/// Groups digits as the collector types, so a five-figure amount can be read back
/// at a glance. The field's value is always major units; the caller converts.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final value = int.tryParse(digits);
    if (value == null) return oldValue;
    final formatted = groupDigits(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String groupDigits(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// The text a [MoneyField] holds for [minor] kobo, grouped the way the formatter
/// would have grouped it had the collector typed it.
String moneyFieldText(int minor) =>
    minor <= 0 ? '' : groupDigits(minor ~/ Money.minorPerMajor);

/// A whole-naira amount field. Kobo are never typed here: a collector takes notes
/// and coins, and no cooperative prices an obligation in kobo.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.hint,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [MoneyInputFormatter()],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '₦ ',
      ),
    );
  }
}

/// Reads a [MoneyField] into kobo.
int moneyFieldMinor(TextEditingController controller) =>
    Money.parseToMinor(controller.text) ?? 0;

/// A line of an amount against a label, the way a receipt reads.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.sublabel,
    this.bold = false,
  });

  final String label;
  final int amount;
  final String? sublabel;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            Money.format(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A grey block that breathes, standing in for a figure that has not arrived.
///
/// A collector on a village link waits several seconds for every list in this app. A
/// spinner over an empty page says only "wait"; the placeholders say what is coming
/// and how much of it, and the page does not jump when the real rows land on top of
/// the same shapes.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.height = 14,
    this.width,
    this.radius = 8,
    this.color = const Color(0xFFEDEEF3),
  });

  final double height;
  final double? width;
  final double radius;

  /// Overridden on the brand surface, where the grey of a white-page placeholder
  /// reads as a rendering fault rather than as something loading.
  final Color color;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Placeholder rows in the shape of the list that is loading.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.count = 5,
    this.height = 68,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final int count;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Skeleton(height: 38, width: 38, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(height: 13, width: 150),
                  SizedBox(height: 8),
                  Skeleton(height: 10, width: 96),
                ],
              ),
            ),
            const Skeleton(height: 12, width: 52),
          ],
        ),
      ),
    );
  }
}

/// How much of a ceiling has been used. Drawn rather than described, because a
/// collector reads "nearly full" off a bar faster than off two figures.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.fraction,
    this.height = 6,
    this.fill = Colors.white,
    this.track = Colors.white24,
  });

  final double fraction;
  final double height;
  final Color fill;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final value = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: track),
            FractionallySizedBox(
              widthFactor: value,
              child: Container(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.ink,
      ),
    );
}
