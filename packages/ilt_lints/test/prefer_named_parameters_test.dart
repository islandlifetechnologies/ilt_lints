// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ilt_lints/ilt_lints.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferNamedParametersTest);
  });
}

@reflectiveTest
class PreferNamedParametersTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferNamedParameters();
    super.setUp();
  }

  Future<void> test_constructorAndMethodExceedingDefaultCount() async {
    await assertDiagnostics(
      r'''
class Example {
  Example(this.a, this.b, this.c);

  final int a;
  final int b;
  final int c;

  void method(int x, int y, [int z = 0]) {}
}
''',
      [lint(25, 24), lint(111, 27)],
    );
  }

  Future<void> test_customCountConfiguredInAnalysisOptions() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - prefer_named_parameters

prefer_named_parameters:
  count: 3
''');

    await assertDiagnostics(
      r'''
void threePositionalAllowed(int a, int b, int c) {}

void fourPositionalFlagged(int a, int b, int c, int d) {}
''',
      [lint(79, 28)],
    );
  }

  Future<void> test_customCountConfiguredUnderPlugins() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - prefer_named_parameters

plugins:
  ilt_lints:
    diagnostics:
      prefer_named_parameters:
        count: 1
''');

    await assertDiagnostics(
      r'''
void onePositionalAllowed(int a) {}

void twoPositionalFlagged(int a, int b) {}
''',
      [lint(62, 14)],
    );
  }

  Future<void> test_defaultCountAllowsUpToTwoPositionalParameters() async {
    await assertNoDiagnostics(r'''
void zeroParams() {}

void onePositional(int a) {}

void twoPositional(int a, String b) {}

void twoPositionalAndNamed(
  int a,
  String b, {
  required bool c,
  int d = 0,
}) {}
''');
  }

  Future<void> test_defaultCountFlagsMoreThanTwoPositionalParameters() async {
    await assertDiagnostics(
      r'''
void threePositional(int a, int b, int c) {}
''',
      [lint(20, 21)],
    );
  }

  Future<void>
  test_fixConvertsConstructorAndOptionalPositionalParameters() async {
    const originalConstructor = r'''
class Example {
  Example(this.a, this.b, this.c);

  final int a;
  final int b;
  final int c;
}
''';

    const expectedConstructor = r'''
class Example {
  Example({required this.a, required this.b, required this.c});

  final int a;
  final int b;
  final int c;
}
''';

    expect(await _applyFix(originalConstructor), expectedConstructor);

    const originalMethod = r'''
void method(int x, int y, [int z = 0]) {}
''';

    const expectedMethod = r'''
void method({required int x, required int y, int z = 0}) {}
''';

    expect(await _applyFix(originalMethod), expectedMethod);
  }

  Future<void>
  test_fixConvertsMixedPositionalAndNamedMultilineParameters() async {
    const original = r'''
void configure(
  int a,
  String b,
  bool c, {
  required int d,
  int e = 0,
}) {}
''';

    const expected = r'''
void configure({
  required int a,
  required String b,
  required bool c,
  required int d,
  int e = 0,
}) {}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_fixConvertsSingleLinePositionalParameters() async {
    const original = r'''
void threePositional(int a, String? b, int c) {}
''';

    const expected = r'''
void threePositional({required int a, required String? b, required int c}) {}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_fixConvertsUserConstructorWithOptionalNullableAge() async {
    const originalSnippet = r'''
const User(String firstName, String lastName, [int? age]) { /* ... */ };
''';

    expect(await _applyFix(originalSnippet), r'''
const User({required String firstName, required String lastName, int? age}) { /* ... */ };
''');

    const originalPrimary = r'''
class const User(String firstName, String lastName, [int? age]) { /* ... */ }
''';

    expect(await _applyFix(originalPrimary), r'''
class const User({required String firstName, required String lastName, int? age}) { /* ... */ }
''');
  }

  Future<void> test_typedefsAndAnonymousFunctionsAreNotFlagged() async {
    await assertNoDiagnostics(r'''
typedef Foo = int Function(bool ascending, dynamic a, dynamic b);

class Client {
  bool Function(Object, String, int)? badCertificateCallback;
}

void main() {
  final f = (int a, int b, int c) => a;
  final g = (_, _, _) => true;
  final client = Client()..badCertificateCallback = (_, _, _) => true;
  f(1, 2, 3);
  g(1, 2, 3);
  client.badCertificateCallback?.call(Object(), '', 0);
}
''');
  }

  Future<void> test_userConstructorWithOptionalNullableAgeDiagnostics() async {
    await assertDiagnostics(
      r'''
class const User(String firstName, String lastName, [int? age]) { /* ... */ }
''',
      [lint(16, 47)],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == PreferNamedParameters.code)
        .toList();
    expect(diagnostics, isNotEmpty);

    final diagnostic = diagnostics.first;
    final context = CorrectionProducerContext.createResolved(
      diagnostic: diagnostic,
      libraryResult: libraryResult,
      selectionLength: diagnostic.length,
      selectionOffset: diagnostic.offset,
      unitResult: unitResult,
    );
    final producer = PreferNamedParametersFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
