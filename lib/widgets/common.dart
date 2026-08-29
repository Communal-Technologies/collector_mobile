import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import '../core/theme.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
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
            Icon(icon, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
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
    this.icon = Icons.info_outline,
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
    final formatted = _group(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _group(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

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
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
