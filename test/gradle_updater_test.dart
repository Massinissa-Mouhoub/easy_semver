import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

/// Kotlin DSL, current Flutter template: Gradle defers to pubspec.yaml.
const _ktsDerived = '''
android {
    namespace = "com.example.my_app"

    defaultConfig {
        applicationId = "com.example.my_app"
        minSdk = flutter.minSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
''';

/// Kotlin DSL with the version pinned in Gradle instead.
const _ktsHardcoded = '''
android {
    defaultConfig {
        applicationId = "com.example.my_app"
        versionCode = 1
        versionName = "1.2.1"
    }
}
''';

/// Groovy, older template: method-call syntax, no `=`.
const _groovyDerived = '''
android {
    defaultConfig {
        applicationId "com.example.my_app"
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
''';

/// Groovy with the version pinned, single-quoted.
const _groovyHardcoded = '''
android {
    defaultConfig {
        versionCode 7
        versionName '1.2.1'
    }
}
''';

void main() {
  const next = Version(1, 4, 0, 2);

  group('when Gradle defers to Flutter', () {
    test('Kotlin DSL is left untouched', () {
      final result = updateGradle(_ktsDerived, next);

      expect(result.fullyDerived, isTrue);
      expect(result.changed, isFalse);
      expect(result.text, _ktsDerived);
    });

    test('Groovy method-call syntax is recognised too', () {
      final result = updateGradle(_groovyDerived, next);

      expect(result.found, isTrue);
      expect(result.versionNameDerived, isTrue);
      expect(result.versionCodeDerived, isTrue);
      expect(result.text, _groovyDerived);
    });
  });

  group('when Gradle hardcodes the version', () {
    test('Kotlin DSL values are rewritten', () {
      final result = updateGradle(_ktsHardcoded, next);

      expect(result.fullyDerived, isFalse);
      expect(result.changed, isTrue);
      expect(result.text, contains('versionName = "1.4.0"'));
      expect(result.text, contains('versionCode = 2'));
    });

    test('Groovy values are rewritten, preserving the quote style', () {
      final result = updateGradle(_groovyHardcoded, next);

      expect(result.text, contains("versionName '1.4.0'"));
      expect(result.text, contains('versionCode 2'));
    });

    test('reports what moved', () {
      final result = updateGradle(_ktsHardcoded, next);
      final described = describeChanges(result.changes)!;
      expect(described, contains('versionName: 1.2.1 -> 1.4.0'));
      expect(described, contains('versionCode: 1 -> 2'));
    });

    test('changes nothing else in the file', () {
      final result = updateGradle(_ktsHardcoded, next);
      expect(result.text, contains('applicationId = "com.example.my_app"'));
    });

    test('re-running at the same version is a no-op', () {
      final result = updateGradle(_ktsHardcoded, const Version(1, 2, 1, 1));
      expect(result.changed, isFalse);
      expect(result.text, _ktsHardcoded);
    });
  });

  group('mixed declarations', () {
    test('a derived name with a pinned code updates only the code', () {
      const mixed = '''
android {
    defaultConfig {
        versionCode = 3
        versionName = flutter.versionName
    }
}
''';
      final result = updateGradle(mixed, next);

      expect(result.versionNameDerived, isTrue);
      expect(result.versionCodeDerived, isFalse);
      expect(result.fullyDerived, isFalse);
      expect(result.text, contains('versionName = flutter.versionName'));
      expect(result.text, contains('versionCode = 2'));
    });
  });

  test('a file with no version declarations is reported', () {
    final result = updateGradle('android {\n}\n', next);
    expect(result.found, isFalse);
    expect(result.changed, isFalse);
  });
}
