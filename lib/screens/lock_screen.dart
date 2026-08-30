import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../state/session_cubit.dart';
import '../widgets/common.dart';
import 'forgot_pin_screen.dart';

/// What a stored session opens on.
///
/// The token in the keystore says which account this is; it does not say who is
/// holding the phone. A collector's phone carries a round's worth of cash movements
/// and the roster of everyone on it, and it gets handed over, left on counters and
/// lost. So the PIN is asked for on every launch, the way the member app asks for
/// it — and unlike the sign-in screen, this asks for the PIN alone: the account has
/// already been established, and sending a code to it every time the app opens would
/// make the app unusable on a round.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (pin.length != AppConfig.pinLength) {
      setState(
        () => _error = 'Enter your ${AppConfig.pinLength}-digit PIN.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final outcome = await context.read<SessionCubit>().unlock(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    // Unlocked and signed out are both the session cubit's to render — the round,
    // or the sign-in screen with its notice — so this screen has nothing to say.
    if (outcome.result == UnlockResult.unlocked ||
        outcome.result == UnlockResult.signedOut) {
      return;
    }
    if (outcome.result == UnlockResult.needsPinSetup) {
      setState(() => _error = outcome.message);
      await _openReset(create: true);
      return;
    }
    _pin.clear();
    setState(() => _error = outcome.message);
  }

  Future<void> _openReset({bool create = false}) async {
    final session = context.read<SessionCubit>().state;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPinScreen(
          login: session.profile?.phone.isNotEmpty == true
              ? session.profile!.phone
              : session.profile?.email ?? '',
          create: create,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of this phone?'),
        content: const Text(
          'Receipts you have already written stay on this phone and go up when '
          'someone signs in with signal. Everything else needs a new sign-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<SessionCubit>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final name = session.profile?.firstName ?? '';
    final grant = session.grant;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                height: 56,
                width: 56,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/images/icon-02.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name.isEmpty ? 'Welcome back' : 'Welcome back, $name',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                grant == null
                    ? 'Enter your PIN to open your round.'
                    : 'Enter your PIN to open your round for '
                          '${grant.cooperativeName}.',
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pin,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: AppConfig.pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 22, letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Notice(
                  text: _error,
                  tone: AppColors.danger,
                  background: AppColors.dangerSoft,
                  icon: Iconsax.danger,
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Unlock'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _busy ? null : () => _openReset(),
                child: const Text('Forgot your PIN?'),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      session.profile?.phone.isNotEmpty == true
                          ? 'Signed in as ${session.profile!.phone}'
                          : 'Signed in as ${session.profile?.email ?? 'this account'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Not you?'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
