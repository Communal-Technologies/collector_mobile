import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/session_cubit.dart';
import '../widgets/common.dart';

/// Step two: the code, the cooperative being signed in for, and — for someone who
/// has never had a PIN — the PIN itself.
///
/// The cooperative is chosen here rather than after signing in because the token
/// carries it: a collector session is a session over one cooperative's round, on
/// that cooperative's terms.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({
    super.key,
    required this.challenge,
    required this.login,
    this.pin = '',
  });

  final LoginChallenge challenge;
  final String login;

  /// What was typed on the sign-in screen. Carried through so the lock this app
  /// opens with can be answered without a connection on the next launch — it is the
  /// only point at which the app holds the PIN in the clear.
  final String pin;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();

  late LoginChallenge _challenge;
  late String _collectorId;
  bool _busy = false;
  bool _resending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _collectorId = _challenge.grants.isNotEmpty
        ? _challenge.grants.first.collectorId
        : '';
  }

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _resend(String channel) async {
    setState(() {
      _resending = true;
      _error = '';
    });
    try {
      final next = await context.read<AuthRepository>().loginResend(
        challengeId: _challenge.challengeId,
        channel: channel,
      );
      if (!mounted) return;
      setState(() {
        // The resend does not repeat the grants, so the ones already on screen and
        // the PIN requirement are carried across.
        _challenge = LoginChallenge(
          challengeId: _challenge.challengeId,
          channel: next.channel.isEmpty ? _challenge.channel : next.channel,
          maskedDestination: next.maskedDestination.isEmpty
              ? _challenge.maskedDestination
              : next.maskedDestination,
          requiresPinSetup: _challenge.requiresPinSetup,
          grants: _challenge.grants,
          message: next.message,
        );
      });
      showToast(context, next.message.isEmpty ? 'Code sent.' : next.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length < AppConfig.otpLength) {
      setState(
        () =>
            _error = 'Enter the ${AppConfig.otpLength}-digit code we sent you.',
      );
      return;
    }
    if (_collectorId.isEmpty) {
      setState(() => _error = 'Choose the cooperative you are collecting for.');
      return;
    }
    String? newPin;
    if (_challenge.requiresPinSetup) {
      newPin = _pin.text.trim();
      if (newPin.length != AppConfig.pinLength) {
        setState(() => _error = 'Choose a ${AppConfig.pinLength}-digit PIN.');
        return;
      }
      if (newPin != _pinConfirm.text.trim()) {
        setState(() => _error = 'The two PINs do not match.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await context.read<AuthRepository>().loginVerify(
        challengeId: _challenge.challengeId,
        code: code,
        collectorId: _collectorId,
        newPin: newPin,
      );
      if (!mounted) return;
      await context.read<SessionCubit>().completeLogin(
        result,
        pin: newPin ?? widget.pin,
      );
      if (!mounted) return;
      // The session cubit decides what is on screen from here; this route and the
      // login screen under it are both done with.
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _destination {
    final masked = _challenge.maskedDestination;
    if (masked.isNotEmpty) return masked;
    return widget.login;
  }

  @override
  Widget build(BuildContext context) {
    final grants = _challenge.grants;
    final offline = isOffline(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Confirm it is you')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We sent a ${AppConfig.otpLength}-digit code to $_destination.',
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: AppConfig.otpLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 22, letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _resending || offline
                        ? null
                        : () => _resend('sms'),
                    child: const Text('Resend by SMS'),
                  ),
                  TextButton(
                    onPressed: _resending || offline
                        ? null
                        : () => _resend('email'),
                    child: const Text('Send by email'),
                  ),
                ],
              ),
              if (grants.length > 1) ...[
                const SizedBox(height: 12),
                const Text(
                  'Which cooperative are you collecting for?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'You can switch later without signing in again.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                ...grants.map(
                  (g) => _GrantChoice(
                    grant: g,
                    selected: g.collectorId == _collectorId,
                    onTap: () => setState(() => _collectorId = g.collectorId),
                  ),
                ),
              ] else if (grants.length == 1) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: grants.first.cooperativeName,
                  child: Text(
                    '${grants.first.collectorCode} · ${grants.first.commissionLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
              if (_challenge.requiresPinSetup) ...[
                const SizedBox(height: 20),
                const Notice(
                  text:
                      'This account has no PIN yet. Choose one now — it is what you '
                      'will sign in with from here on, and it is the same PIN the '
                      'member app uses.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: AppConfig.pinLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Choose a 6-digit PIN',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinConfirm,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: AppConfig.pinLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Confirm your PIN',
                    counterText: '',
                  ),
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Notice(
                  text: _error,
                  tone: AppColors.danger,
                  background: AppColors.dangerSoft,
                  icon: Iconsax.danger,
                ),
              ],
              const SizedBox(height: 24),
              const OfflineNotice(
                reason:
                    'The code can only be checked by Communal, so this last step '
                    'needs a connection.',
              ),
              FilledButton(
                onPressed: _busy || offline ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(offline ? 'Waiting for a connection' : 'Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrantChoice extends StatelessWidget {
  const _GrantChoice({
    required this.grant,
    required this.selected,
    required this.onTap,
  });

  final CollectorGrant grant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grant.cooperativeName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${grant.collectorCode} · ${grant.commissionLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Iconsax.tick_circle5 : Iconsax.record_circle,
                color: selected ? AppColors.primary : AppColors.line,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
