import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../legal/privacy_policy.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../ui_text.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onCreateAccount});

  /// Optional seam for exercising the email-confirmation flow without a
  /// network-backed Supabase project in widget tests.
  final Future<String?> Function(String email, String password)?
      onCreateAccount;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _creatingAccount = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  bool _messageIsError = false;

  String _copy(String en, String th) => uiText(context, english: en, thai: th);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: AppLanguageToggle(
                    language: context.watch<DozState>().language,
                    onChanged: (language) => unawaited(
                      context
                          .read<DozState>()
                          .updateSettings(newLanguage: language),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF12352F),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.watch_outlined,
                      size: 34, color: Color(0xFF55D6A7)),
                ),
                const SizedBox(height: 20),
                Text(
                    _creatingAccount
                        ? _copy('Create your doz account', 'สร้างบัญชี doz')
                        : _copy('Welcome back', 'ยินดีต้อนรับกลับ'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                const SizedBox(height: 8),
                Text(_creatingAccount
                    ? _copy(
                        'Sign up with email. You may need to verify it before signing in.',
                        'สมัครด้วยอีเมล ระบบอาจส่งลิงก์ยืนยันก่อนเข้าใช้งาน')
                    : _copy('Sign in to open this account’s on-device profile.',
                        'เข้าสู่ระบบเพื่อเปิดโปรไฟล์ในเครื่องของบัญชีนี้')),
                const SizedBox(height: 24),
                AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: _copy('Email', 'อีเมล'),
                            prefixIcon: const Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final email = (value ?? '').trim();
                            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(email)) {
                              return _copy('Enter a valid email address.',
                                  'กรอกอีเมลให้ถูกต้อง');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          textInputAction: _creatingAccount
                              ? TextInputAction.next
                              : TextInputAction.done,
                          autofillHints: _creatingAccount
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: _copy('Password', 'รหัสผ่าน'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? _copy('Show password', 'แสดงรหัสผ่าน')
                                  : _copy('Hide password', 'ซ่อนรหัสผ่าน'),
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 8) {
                              return _copy('Use at least 8 characters.',
                                  'ใช้รหัสผ่านอย่างน้อย 8 ตัวอักษร');
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) {
                            if (_creatingAccount) {
                              FocusScope.of(context).nextFocus();
                            } else {
                              _submit();
                            }
                          },
                        ),
                        if (_creatingAccount) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPassword,
                            obscureText: _hidePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText:
                                  _copy('Confirm password', 'ยืนยันรหัสผ่าน'),
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                            ),
                            validator: (value) {
                              if ((value ?? '').isEmpty) {
                                return _copy('Confirm your password.',
                                    'กรอกยืนยันรหัสผ่าน');
                              }
                              if (value != _password.text) {
                                return _copy('Passwords do not match.',
                                    'รหัสผ่านไม่ตรงกัน');
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _messageIsError
                            ? const Color(0xFFFF8585)
                            : const Color(0xFF55D6A7),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? Semantics(
                          label: _copy('Please wait', 'โปรดรอสักครู่'),
                          liveRegion: true,
                          child: const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(_creatingAccount
                          ? _copy('Create account', 'สมัครบัญชี')
                          : _copy('Sign in', 'เข้าสู่ระบบ')),
                ),
                if (!_creatingAccount)
                  TextButton(
                    onPressed: _busy ? null : _resetPassword,
                    child: Text(_copy('Forgot password?', 'ลืมรหัสผ่าน')),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _creatingAccount = !_creatingAccount;
                            _message = null;
                            _messageIsError = false;
                            _confirmPassword.clear();
                          }),
                  child: Text(_creatingAccount
                      ? _copy('Already have an account? Sign in',
                          'มีบัญชีแล้ว? เข้าสู่ระบบ')
                      : _copy('New to doz? Create an account',
                          'ยังไม่มีบัญชี? สมัครใหม่')),
                ),
                const SizedBox(height: 8),
                Text(
                  _copy(
                    'Profile and alert history stay on this device and do not sync across devices. Signing in does not make cloud health-data services secure by itself.',
                    'ข้อมูลในโปรไฟล์และประวัติยังเก็บในเครื่องนี้ ไม่ได้ซิงก์ข้ามอุปกรณ์ การเข้าสู่ระบบไม่ทำให้บริการ Cloud health data ปลอดภัยขึ้นโดยอัตโนมัติ',
                  ),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFF8B93A3), fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () => showPrivacyPolicyDialog(
                    context,
                    allowAccept: false,
                  ),
                  icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                  label: Text(_copy(
                    'Read privacy notice (draft)',
                    'อ่านประกาศความเป็นส่วนตัว (ฉบับร่าง)',
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final email = _email.text.trim();
      if (_creatingAccount) {
        final userId = await (widget.onCreateAccount ?? _createAccount)(
          email,
          _password.text,
        );
        if (!mounted) return;
        if (userId == null) {
          TextInput.finishAutofillContext(shouldSave: false);
          setState(() {
            _creatingAccount = false;
            _password.clear();
            _confirmPassword.clear();
            _message = _copy(
                'Account created. Verify your email, then return to sign in.',
                'สมัครสำเร็จแล้ว โปรดยืนยันอีเมล จากนั้นกลับมาเข้าสู่ระบบ');
            _messageIsError = false;
          });
        } else {
          await _enterAccount(userId);
        }
      } else {
        final response = await AuthService.signIn(email, _password.text);
        if (!mounted) return;
        final user = response.user;
        if (user == null) throw StateError('ไม่พบผู้ใช้ที่ยืนยันตัวตน');
        await _enterAccount(user.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = _copy(
              'Could not continue. Check your email, password, email verification, and Auth configuration.',
              'ดำเนินการไม่สำเร็จ ตรวจสอบอีเมล/รหัสผ่าน การยืนยันอีเมล และการตั้งค่า Auth');
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterAccount(String userId) async {
    TextInput.finishAutofillContext(shouldSave: true);
    await context.read<DozState>().bindAuthenticatedUser(userId);
  }

  Future<String?> _createAccount(String email, String password) async {
    final response = await AuthService.signUp(email, password);
    if (response.session == null) return null;
    final userId = response.user?.id;
    if (userId == null || userId.isEmpty) {
      throw StateError('Authenticated sign-up did not return a user ID');
    }
    return userId;
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _message = _copy('Enter your email to request a password reset link.',
            'กรอกอีเมลก่อนขอลิงก์ตั้งรหัสผ่านใหม่');
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      await AuthService.sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _message = _copy(
            'Request sent. Check your email for the password reset link.',
            'ส่งคำขอแล้ว โปรดตรวจอีเมลและลิงก์ตั้งรหัสผ่าน');
        _messageIsError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = _copy(
              'Could not send email. Check the Auth configuration.',
              'ส่งอีเมลไม่สำเร็จ ตรวจสอบการตั้งค่า Auth');
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
