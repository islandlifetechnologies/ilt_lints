import 'dart:io';

import 'package:ilt_lints/ilt_lints.dart';
import 'package:test/test.dart';

void main() {
  group('bin/fix.dart (runFixCli)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ilt_lints_fix_cli_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('prints usage with --help', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runFixCli(
        ['--help'],
        err: err,
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('Usage: dart run ilt_lints:fix'));
      expect(err.toString(), isEmpty);
    });

    test('returns 64 on unknown option or missing path', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final badFlagCode = await runFixCli(
        ['--unknown-flag'],
        err: err,
        out: out,
        workingDirectory: tempDir.path,
      );
      expect(badFlagCode, 64);
      expect(err.toString(), contains('Unknown option: --unknown-flag'));

      err.clear();
      final missingPathCode = await runFixCli(
        ['does_not_exist.dart'],
        err: err,
        out: out,
        workingDirectory: tempDir.path,
      );
      expect(missingPathCode, 64);
      expect(err.toString(), contains('Path does not exist: does_not_exist.dart'));
    });

    test('applies fixes for all enabled custom lints', () async {
      File('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^1.1.0
    diagnostics:
      sort_fields: true
      sort_functions_alphabetically: true
      sort_functions_by_scope: true
      sort_named_parameters: true
''');

      final dartFile = File('${tempDir.path}/example.dart');
      dartFile.writeAsStringSync(r'''
class Example {
  Example({required this.beta, required this.alpha});

  void _privateMethod() {}

  void zebraPublic({int? b, int? a}) {}

  void alphaPublic() {
    zebraPublic(b: 2, a: 1);
  }

  final int beta;
  final int alpha;
}
''');

      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runFixCli(
        [tempDir.path],
        err: err,
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('Applying fixes...'));
      expect(out.toString(), contains('sort_fields'));
      expect(out.toString(), contains('sort_functions_by_scope'));
      expect(out.toString(), contains('sort_functions_alphabetically'));
      expect(out.toString(), contains('sort_named_parameters'));

      expect(
        dartFile.readAsStringSync(),
        r'''
class Example {
  Example({required this.alpha, required this.beta});

  final int alpha;

  final int beta;

  void alphaPublic() {
    zebraPublic(a: 1, b: 2);
  }

  void zebraPublic({int? a, int? b}) {}
  void _privateMethod() {}
}
''',
      );
    });

    test('only applies fixes for rules that are enabled', () async {
      File('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^1.1.0
    diagnostics:
      sort_fields: false
      sort_functions_alphabetically: true
      sort_functions_by_scope: false
      sort_named_parameters: false
''');

      final dartFile = File('${tempDir.path}/example.dart');
      dartFile.writeAsStringSync(r'''
class Example {
  void beta({int? b, int? a}) {}

  void alpha() {}

  final int zField = 1;
  final int aField = 2;
}
''');

      final out = StringBuffer();
      final exitCode = await runFixCli(
        [tempDir.path],
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('sort_functions_alphabetically'));
      expect(out.toString(), isNot(contains('sort_fields')));
      expect(out.toString(), isNot(contains('sort_named_parameters')));

      // Methods are sorted alphabetically, while fields and named parameters
      // remain untouched because their rules are disabled.
      expect(
        dartFile.readAsStringSync(),
        r'''
class Example {
  void alpha() {}

  void beta({int? b, int? a}) {}

  final int zField = 1;
  final int aField = 2;
}
''',
      );
    });

    test('--dry-run reports fixes without modifying files on disk', () async {
      File('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^1.1.0
    diagnostics:
      sort_functions_alphabetically: true
''');

      const original = r'''
class Example {
  void beta() {}
  void alpha() {}
}
''';
      final dartFile = File('${tempDir.path}/example.dart')
        ..writeAsStringSync(original);

      final out = StringBuffer();
      final exitCode = await runFixCli(
        ['--dry-run', tempDir.path],
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(
         exitCode, 0);
      expect(out.toString(), contains('Fixes that would be applied:'));
      expect(out.toString(), contains('sort_functions_alphabetically (1 fix)'));
      expect(dartFile.readAsStringSync(), original);
    });

    test('applies export_library fixes via CLI', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: sample_pkg
''');
      File('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^2.0.0
    diagnostics:
      export_library: true
''');

      Directory('${tempDir.path}/lib/src').createSync(recursive: true);
      File('${tempDir.path}/lib/src/alpha.dart').writeAsStringSync(
        'class Alpha {}\n',
      );
      File('${tempDir.path}/lib/src/beta.dart').writeAsStringSync(
        'class Beta {}\n',
      );
      final exporterFile = File('${tempDir.path}/lib/sample_pkg.dart')
        ..writeAsStringSync("export 'src/beta.dart';\n");

      final out = StringBuffer();
      final exitCode = await runFixCli(
        [tempDir.path],
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('export_library (1 fix)'));
      expect(
        exporterFile.readAsStringSync(),
        "export 'src/alpha.dart';\nexport 'src/beta.dart';\n",
      );
    });

    test('applies valid_json_serializable fixes via CLI', () async {
      File('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^2.0.0
    diagnostics:
      valid_json_serializable: true
''');

      final dartFile = File('${tempDir.path}/model.dart');
      dartFile.writeAsStringSync(r'''
class JsonSerializable {
  const JsonSerializable();
}

@JsonSerializable()
class User {
  final String name;

  User(this.name);
}
''');

      final out = StringBuffer();
      final exitCode = await runFixCli(
        [tempDir.path],
        out: out,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('valid_json_serializable (1 fix)'));
      final content = dartFile.readAsStringSync();
      expect(content, contains(r'factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);'));
      expect(content, contains(r'Map<String, dynamic> toJson() => _$UserToJson(this);'));
    });
  });
}
