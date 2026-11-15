import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:ilt_lints/ilt_lints.dart';
import 'package:meta/meta.dart';
import 'package:quick_fix/quick_fix.dart';
import 'package:test/test.dart';

final _ruleEntries = <RuleFixEntry>[
  RuleFixEntry(
    fixGenerator: ExportLibraryFix.new,
    name: ExportLibrary.code.lowerCaseName,
    ruleFactory: ExportLibrary.new,
  ),
  RuleFixEntry(
    fixGenerator: PreferConstConstructorsFix.new,
    name: PreferConstConstructors.code.lowerCaseName,
    ruleFactory: PreferConstConstructors.new,
  ),
  RuleFixEntry(
    fixGenerator: PreferPrimaryConstructorsFix.new,
    name: PreferPrimaryConstructors.code.lowerCaseName,
    ruleFactory: PreferPrimaryConstructors.new,
  ),
  RuleFixEntry(
    fixGenerator: SortFieldsFix.new,
    name: SortFields.code.lowerCaseName,
    ruleFactory: SortFields.new,
  ),
  RuleFixEntry(
    fixGenerator: SortFunctionsByScopeFix.new,
    name: SortFunctionsByScope.code.lowerCaseName,
    ruleFactory: SortFunctionsByScope.new,
  ),
  RuleFixEntry(
    fixGenerator: SortFunctionsAlphabeticallyFix.new,
    name: SortFunctionsAlphabetically.code.lowerCaseName,
    ruleFactory: SortFunctionsAlphabetically.new,
  ),
  RuleFixEntry(
    fixGenerator: SortNamedParametersFix.new,
    name: SortNamedParameters.code.lowerCaseName,
    ruleFactory: SortNamedParameters.new,
  ),
  RuleFixEntry(
    fixGenerator: UseClockFix.new,
    name: UseClock.code.lowerCaseName,
    ruleFactory: UseClock.new,
  ),
  RuleFixEntry(
    fixGenerator: UseFileSystemFix.new,
    name: UseFileSystem.code.lowerCaseName,
    ruleFactory: UseFileSystem.new,
  ),
  RuleFixEntry(
    fixGenerator: ValidJsonSerializableFix.new,
    name: ValidJsonSerializable.code.lowerCaseName,
    ruleFactory: ValidJsonSerializable.new,
  ),
];

void main({@visibleForTesting FileSystem fs = const LocalFileSystem()}) {
  group('bin/fix.dart (runQuickFixCli)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = fs.systemTempDirectory.createTempSync(
        'ilt_lints_fix_cli_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('prints usage with --help', () async {
      final out = StringBuffer();
      final err = StringBuffer();

      final exitCode = await runQuickFixCli(
        ['--help'],
        err: err,
        out: out,
        ruleEntries: _ruleEntries,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('Applies automated fixes for all'));
      expect(err.toString(), isEmpty);
    });

    test('applies fixes for all enabled custom lints', () async {
      fs.file('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^1.1.0
    diagnostics:
      sort_fields: true
      sort_functions_alphabetically: true
      sort_functions_by_scope: true
      sort_named_parameters: true
''');

      final dartFile = fs.file('${tempDir.path}/example.dart');
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

      final exitCode = await runQuickFixCli(
        [tempDir.path],
        err: err,
        out: out,
        ruleEntries: _ruleEntries,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('Applying fixes...'));
      expect(out.toString(), contains('sort_fields'));
      expect(out.toString(), contains('sort_functions_by_scope'));
      expect(out.toString(), contains('sort_functions_alphabetically'));
      expect(out.toString(), contains('sort_named_parameters'));

      expect(dartFile.readAsStringSync(), r'''
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
''');
    });

    test('only applies fixes for rules that are enabled', () async {
      fs.file('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^1.1.0
    diagnostics:
      sort_fields: false
      sort_functions_alphabetically: true
      sort_functions_by_scope: false
      sort_named_parameters: false
''');

      final dartFile = fs.file('${tempDir.path}/example.dart');
      dartFile.writeAsStringSync(r'''
class Example {
  void beta({int? b, int? a}) {}

  void alpha() {}

  final int zField = 1;
  final int aField = 2;
}
''');

      final out = StringBuffer();
      final exitCode = await runQuickFixCli(
        [tempDir.path],
        out: out,
        ruleEntries: _ruleEntries,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('sort_functions_alphabetically'));
      expect(out.toString(), isNot(contains('sort_fields')));
      expect(out.toString(), isNot(contains('sort_named_parameters')));

      // Methods are sorted alphabetically, while fields and named parameters
      // remain untouched because their rules are disabled.
      expect(dartFile.readAsStringSync(), r'''
class Example {
  void alpha() {}

  void beta({int? b, int? a}) {}

  final int zField = 1;
  final int aField = 2;
}
''');
    });

    test('--dry-run reports fixes without modifying files on disk', () async {
      fs.file('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
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
      final dartFile = fs.file('${tempDir.path}/example.dart')
        ..writeAsStringSync(original);

      final out = StringBuffer();
      final exitCode = await runQuickFixCli(
        ['--dry-run', tempDir.path],
        out: out,
        ruleEntries: _ruleEntries,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('Fixes that would be applied:'));
      expect(out.toString(), contains('sort_functions_alphabetically (1 fix)'));
      expect(dartFile.readAsStringSync(), original);
    });

    test('applies export_library fixes via CLI', () async {
      fs.file('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: sample_pkg
''');
      fs.file('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^2.0.0
    diagnostics:
      export_library: true
''');

      fs.directory('${tempDir.path}/lib/src').createSync(recursive: true);
      fs
          .file('${tempDir.path}/lib/src/alpha.dart')
          .writeAsStringSync('class Alpha {}\n');
      fs
          .file('${tempDir.path}/lib/src/beta.dart')
          .writeAsStringSync('class Beta {}\n');
      final exporterFile = fs.file('${tempDir.path}/lib/sample_pkg.dart')
        ..writeAsStringSync("export 'src/beta.dart';\n");

      final out = StringBuffer();
      final exitCode = await runQuickFixCli(
        [tempDir.path],
        out: out,
        ruleEntries: _ruleEntries,
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
      fs.file('${tempDir.path}/analysis_options.yaml').writeAsStringSync('''
plugins:
  ilt_lints:
    version: ^2.0.0
    diagnostics:
      valid_json_serializable: true
''');

      final dartFile = fs.file('${tempDir.path}/model.dart');
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
      final exitCode = await runQuickFixCli(
        [tempDir.path],
        out: out,
        ruleEntries: _ruleEntries,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(out.toString(), contains('valid_json_serializable (1 fix)'));
      final content = dartFile.readAsStringSync();
      expect(content, contains("part 'model.g.dart';"));
      expect(
        content,
        contains(
          r'factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);',
        ),
      );
      expect(
        content,
        contains(r'Map<String, dynamic> toJson() => _$UserToJson(this);'),
      );
    });
  });
}
