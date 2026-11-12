import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

/// Login only. There is intentionally NO sign-up flow: accounts are created
/// by an administrator (public registration is disabled).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Router redirect moves the user to /home automatically.
    } on AuthException catch (e) {
      setState(() => _error = _friendly(e.message));
    } catch (_) {
      setState(() => _error =
          'Network error. Check your connection and try again. / নেটওয়ার্ক সমস্যা, আবার চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first. / আগে ইমেইল লিখুন।');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'If the account exists, a reset link was sent. / রিসেট লিংক পাঠানো হয়েছে।'),
      ));
    } catch (_) {
      setState(() => _error = 'Could not send reset email. / ইমেইল পাঠানো যায়নি।');
    }
  }

  String _friendly(String raw) {
    // Generic message on purpose: do not reveal whether an email exists.
    return 'Invalid email or password. / ইমেইল বা পাসওয়ার্ড ভুল।';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.school_rounded,
                        size: 64, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text('DPI Department Hub',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )),
                    const Text('Daffodil Polytechnic Institute',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email / ইমেইল',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty || !value.contains('@')) {
                          return 'Enter a valid email / সঠিক ইমেইল লিখুন';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password / পাসওয়ার্ড',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password / পাসওয়ার্ড লিখুন'
                          : null,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in / প্রবেশ করুন'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _forgotPassword,
                      child: const Text('Forgot password? / পাসওয়ার্ড ভুলে গেছেন?'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Accounts are created by the administrator. / অ্যাকাউন্ট প্রশাসক তৈরি করেন।',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
