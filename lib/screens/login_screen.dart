import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/repository.dart';
import '../state/session_cubit.dart';
import '../widgets/common.dart';
import 'verify_screen.dart';

/// Step one of signing in: who is this, and do they already have a PIN.
///
/// A collector signs in with the Communal account they already have — the
/// cooperative gives that account the collector role, it does not issue a login or
/// a phone number and email of its own. Whether the PIN is required is still not
/// something this screen can know: an account that has never opened the member app
/// has no PIN yet. So the field is offered and explained rather than demanded, and
/// the server decides.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _login.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(
        () => _error =
            'Enter the phone number or email you use for Communal.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final challenge = await context.read<AuthRepository>().loginRequest(
        login: login,
        pin: _pin.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyScreen(challenge: challenge, login: login),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = context.select((SessionCubit c) => c.state.notice);
    final offline = isOffline(context);
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
              const Text(
                'Collector sign-in',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in with your Communal account — the same phone number or email '
                'and the same PIN. There is nothing to sign up for here: your '
                'cooperative gives an account you already have the collector role.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 24),
              if (notice.isNotEmpty) ...[
                Notice(text: notice),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _login,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Phone number or email',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: AppConfig.pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                  helperMaxLines: 3,
                  helperText:
                      'The same 6-digit PIN as the Communal app. Leave it blank only if '
                      'you have never set one — then you will choose it next.',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Notice(
                  text: _error,
                  tone: AppColors.danger,
                  background: AppColors.dangerSoft,
                  icon: Icons.error_outline,
                ),
              ],
              const SizedBox(height: 22),
              const OfflineNotice(
                reason:
                    'Signing in needs a connection — the code has to be sent to '
                    'you and checked.',
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
                    : Text(
                        offline ? 'Waiting for a connection' : 'Send my code',
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                'We send a 6-digit code to the phone number or email on your '
                'Communal account.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
