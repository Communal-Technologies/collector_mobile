import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsax/iconsax.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/repository.dart';
import '../state/session_cubit.dart';
import '../widgets/common.dart';

/// Getting a PIN back, or getting one for the first time.
///
/// The same three calls the member app's forgot-password screens make, in one
/// screen because a collector is standing somewhere doing this rather than sitting
/// down: a code out, the code and the new PIN back. It is one PIN on one account, so
/// what is set here is what the member app will want next time too — and that is
/// said on the screen, because a collector who did not expect it would think their
/// member app had broken.
///
/// [create] only changes the wording. An account with no PIN and an account whose
/// owner has forgotten theirs need exactly the same proof: a code sent to the phone
/// number or email the account already holds.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, this.login = '', this.create = false});

  /// Prefilled from the session where there is one. Editable, because the account
  /// may have both a phone number and an email and only one of them may be reachable
  /// where the collector is standing.
  final String login;

  final bool create;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _login = TextEditingController();
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();

  bool _sent = false;
  bool _busy = false;
  String _error = '';
  String _sentMessage = '';

  @override
  void initState() {
    super.initState();
    _login.text = widget.login;
  }

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(
        () => _error = 'Enter the phone number or email on your Communal account.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final message = await context.read<AuthRepository>().pinResetRequest(login);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentMessage = message;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPin() async {
    final login = _login.text.trim();
    final code = _code.text.trim();
    final pin = _pin.text.trim();
    if (code.length != AppConfig.otpLength) {
      setState(
        () => _error = 'Enter the ${AppConfig.otpLength}-digit code we sent you.',
      );
      return;
    }
    if (pin.length != AppConfig.pinLength) {
      setState(() => _error = 'Choose a ${AppConfig.pinLength}-digit PIN.');
      return;
    }
    if (pin != _pinConfirm.text.trim()) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final auth = context.read<AuthRepository>();
      // Verified on its own first, so a wrong code is said as a wrong code rather
      // than as whatever the set call would have made of it.
      await auth.pinResetVerify(login: login, code: code);
      await auth.pinResetSet(login: login, code: code, newPin: pin);
      if (!mounted) return;
      // Straight through the lock on the new PIN: the collector has just typed it
      // twice, and a lock screen asking for it a third time is a screen that reads
      // as a failure.
      final session = context.read<SessionCubit>();
      final outcome = session.state.status == SessionStatus.signedIn
          ? await session.unlock(pin)
          : const UnlockOutcome(UnlockResult.unlocked);
      if (!mounted) return;
      // Said before the pop, because the messenger is looked up through this
      // screen's context and it is about to stop existing.
      showToast(
        context,
        outcome.result == UnlockResult.unlocked
            ? 'Your PIN is set. It is the same PIN the Communal app uses.'
            : 'Your PIN is set. Enter it to unlock.',
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = isOffline(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.create ? 'Create your PIN' : 'Reset your PIN'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.create
                    ? 'Your account does not have a PIN yet. We send a code to the '
                          'phone number or email on it, and then you choose one.'
                    : 'We send a code to the phone number or email on your Communal '
                          'account, and then you choose a new PIN.',
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _login,
                enabled: !_sent,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Phone number or email',
                ),
              ),
              if (_sent) ...[
                const SizedBox(height: 16),
                Notice(
                  text: _sentMessage.isEmpty
                      ? 'We sent you a ${AppConfig.otpLength}-digit code.'
                      : _sentMessage,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: AppConfig.otpLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 22, letterSpacing: 8),
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: AppConfig.pinLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: widget.create
                        ? 'Choose a ${AppConfig.pinLength}-digit PIN'
                        : 'New ${AppConfig.pinLength}-digit PIN',
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
                const SizedBox(height: 14),
                const Notice(
                  text: 'This is your Communal PIN, not a collector-only one. The '
                      'member app will want this new PIN too.',
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
              const SizedBox(height: 22),
              const OfflineNotice(
                reason: 'The code has to be sent to you and checked, so this needs '
                    'a connection.',
              ),
              FilledButton(
                onPressed: _busy || offline
                    ? null
                    : (_sent ? _setPin : _sendCode),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        offline
                            ? 'Waiting for a connection'
                            : (_sent ? 'Set my PIN' : 'Send my code'),
                      ),
              ),
              if (_sent) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy || offline ? null : _sendCode,
                  child: const Text('Send the code again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
