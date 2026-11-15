import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../ui_text.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  // EN: Show this page only after the Auth recovery route is received.
  // TH: แสดงหน้านี้หลังได้รับเส้นทางกู้คืนจากระบบ Auth
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  // EN: Keep new credentials in memory only until submission or disposal.
  // TH: เก็บรหัสผ่านใหม่ในหน่วยความจำจนกว่าจะส่งหรือปิดหน้า
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  String _copy(String en, String th) => uiText(context, english: en, thai: th);

  @override
  void dispose() {
    // EN: Release both password controllers when this screen is removed.
    // TH: คืน controller ของรหัสผ่านทั้งสองช่องเมื่อออกจากหน้านี้
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text(_copy('Reset password', 'ตั้งรหัสผ่านใหม่'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(_copy('Choose a new password with at least 8 characters.',
                    'ตั้งรหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร')),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: _copy('New password', 'รหัสผ่านใหม่')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmation,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: _copy('Confirm password', 'ยืนยันรหัสผ่าน')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? Semantics(
                          label: _copy('Please wait', 'โปรดรอสักครู่'),
                          liveRegion: true,
                          child: const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(_copy('Save password', 'บันทึกรหัสผ่าน')),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _save() async {
    // EN: Check matching passwords locally before invoking the Auth service.
    // TH: ตรวจว่ารหัสผ่านตรงกันในเครื่องก่อนเรียกบริการ Auth
    final password = _password.text;
    if (password.length < 8 || password != _confirmation.text) {
      setState(() => _error = _copy(
          'Passwords must be at least 8 characters and match.',
          'รหัสผ่านต้องอย่างน้อย 8 ตัวและต้องตรงกัน'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = context.read<DozState>();
      await AuthService.updatePassword(password);
      // EN: Do not touch the widget tree after an asynchronous completion if unmounted.
      // TH: ไม่ใช้งาน widget tree หลังงาน async หากหน้าถูกปิดไปแล้ว
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy(
            'Password updated. Sign in with your new password.',
            'เปลี่ยนรหัสผ่านแล้ว โปรดเข้าสู่ระบบด้วยรหัสผ่านใหม่',
          )),
        ),
      );
      await state.logout();
      if (!mounted) return;
    } catch (_) {
      if (mounted) {
        setState(() => _error = _copy(
            'Could not update password. The link may have expired; request a new one.',
            'ตั้งรหัสผ่านไม่สำเร็จ ลิงก์อาจหมดอายุ โปรดลองใหม่'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
