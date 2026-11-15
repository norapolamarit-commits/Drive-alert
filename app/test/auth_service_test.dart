import 'dart:convert';
import 'dart:io';

import 'package:doz/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth deep link is registered by both mobile platforms', () {
    final redirect = Uri.parse(AuthService.redirectUri);
    final androidManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final iosPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(redirect.scheme, 'doz');
    expect(redirect.host, 'login-callback');
    expect(androidManifest, contains('android:scheme="${redirect.scheme}"'));
    expect(androidManifest, contains('android:host="${redirect.host}"'));
    expect(
      iosPlist,
      contains(
        RegExp(
          r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>doz</string>',
        ),
      ),
    );
  });

  group('authConfigurationError', () {
    test('allows local demo only in debug builds', () {
      expect(
        authConfigurationError(url: '', publishableKey: '', releaseMode: false),
        isNull,
      );
      expect(
        authConfigurationError(url: '', publishableKey: '', releaseMode: true),
        contains('debug-only'),
      );
    });

    test('requires both URL and publishable key when partially configured', () {
      expect(
        authConfigurationError(
          url: 'https://doz-project.supabase.co',
          publishableKey: '',
          releaseMode: false,
        ),
        contains('Set both'),
      );
      expect(
        authConfigurationError(
          url: '',
          publishableKey: 'sb_publishable_example',
          releaseMode: false,
        ),
        contains('Set both'),
      );
    });

    test('rejects non-HTTPS remote URLs and URLs containing credentials', () {
      expect(
        authConfigurationError(
          url: 'http://doz-project.supabase.co',
          publishableKey: 'sb_publishable_example',
          releaseMode: true,
        ),
        contains('HTTPS'),
      );
      expect(
        authConfigurationError(
          url: 'https://user:password@doz-project.supabase.co',
          publishableKey: 'sb_publishable_example',
          releaseMode: true,
        ),
        contains('HTTPS'),
      );
    });

    test('allows localhost only in debug builds', () {
      expect(
        authConfigurationError(
          url: 'http://localhost:54321',
          publishableKey: 'sb_publishable_example',
          releaseMode: false,
        ),
        isNull,
      );
      expect(
        authConfigurationError(
          url: 'http://localhost:54321',
          publishableKey: 'sb_publishable_example',
          releaseMode: true,
        ),
        contains('debug-only'),
      );
      expect(
        authConfigurationError(
          url: 'https://localhost:54321',
          publishableKey: 'sb_publishable_example',
          releaseMode: true,
        ),
        contains('debug-only'),
      );
    });

    test('rejects service-role keys and accepts an HTTPS public project key',
        () {
      expect(
        authConfigurationError(
          url: 'https://doz-project.supabase.co',
          publishableKey: 'service_role_secret',
          releaseMode: true,
        ),
        contains('never embed secret keys'),
      );
      expect(
        authConfigurationError(
          url: 'https://doz-project.supabase.co',
          publishableKey: 'sb_publishable_example',
          releaseMode: true,
        ),
        isNull,
      );
      expect(
        authConfigurationError(
          url: 'https://doz-project.supabase.co',
          publishableKey: 'sb_secret_do_not_embed',
          releaseMode: true,
        ),
        contains('never embed secret keys'),
      );
    });

    test('accepts legacy anon JWTs but rejects privileged or malformed JWTs',
        () {
      String legacyJwt(String role) {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({'role': role})))
            .replaceAll('=', '');
        return 'header.$payload.signature';
      }

      String? validate(String key) => authConfigurationError(
            url: 'https://doz-project.supabase.co',
            publishableKey: key,
            releaseMode: true,
          );

      expect(validate(legacyJwt('anon')), isNull);
      expect(validate(legacyJwt('service_role')), contains('anon JWT'));
      expect(validate(legacyJwt('supabase_admin')), contains('anon JWT'));
      expect(validate('not.a.jwt'), contains('anon JWT'));
    });

    test('rejects Supabase URLs that are not project-root origins', () {
      for (final url in [
        'https://doz-project.supabase.co/rest/v1',
        'https://doz-project.supabase.co/?redirect=https://attacker.example',
        'https://doz-project.supabase.co/#fragment',
      ]) {
        expect(
          authConfigurationError(
            url: url,
            publishableKey: 'sb_publishable_example',
            releaseMode: true,
          ),
          isNotNull,
          reason: 'Unexpected Supabase URL accepted: $url',
        );
      }
    });

    test('rejects IPv4 and IPv6 loopback destinations for release builds', () {
      for (final url in [
        'http://127.0.0.1:54321',
        'https://[::1]:54321',
        'https://api.localhost',
      ]) {
        expect(
          authConfigurationError(
            url: url,
            publishableKey: 'sb_publishable_example',
            releaseMode: true,
          ),
          contains('debug-only'),
          reason: 'Loopback destination accepted in release: $url',
        );
      }
    });
  });
}
