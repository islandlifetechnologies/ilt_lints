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
    defineReflectiveTests(SortNamedParametersTest);
  });
}

@reflectiveTest
class SortNamedParametersTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortNamedParameters();
    super.setUp();
  }

  Future<void> test_constructorCallNamedArgumentsUnsorted() async {
    await assertDiagnostics(
      r'''
class Example {
  Example({int? alpha, int? beta});
}

void caller() {
  Example(beta: 2, alpha: 1);
}
''',
      [lint(90, 5)],
    );
  }

  Future<void> test_constructorDeclarationNamedParametersUnsorted() async {
    await assertDiagnostics(
      r'''
class Example {
  final int alpha;
  final int beta;

  Example({required this.beta, required this.alpha});
}
''',
      [lint(99, 5)],
    );
  }

  Future<void>
  test_fixSortsDeclarationAndCallSitePreservingIgnoredParameters() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

sort_named_parameters:
  ignore:
    - key
    - child
''');

    const originalDecl = r'''
class Widget {
  const Widget(
    int pos, {
    String? key,
    required int charlie,
    int bravo = 2,
    int? alpha,
    Widget? child,
  });
}
''';

    const expectedDecl = r'''
class Widget {
  const Widget(
    int pos, {
    String? key,
    int? alpha,
    int bravo = 2,
    required int charlie,
    Widget? child,
  });
}
''';

    final fixedDecl = await _applyFix(originalDecl);
    expect(fixedDecl, expectedDecl);

    const originalCall = r'''
class Widget {
  const Widget(
    int pos, {
    String? key,
    int? alpha,
    int bravo = 2,
    required int charlie,
    Widget? child,
  });
}

Widget build() {
  return const Widget(
    1,
    key: 'k',
    charlie: 3,
    bravo: 2,
    alpha: 1,
    child: null,
  );
}
''';

    const expectedCall = r'''
class Widget {
  const Widget(
    int pos, {
    String? key,
    int? alpha,
    int bravo = 2,
    required int charlie,
    Widget? child,
  });
}

Widget build() {
  return const Widget(
    1,
    key: 'k',
    alpha: 1,
    bravo: 2,
    charlie: 3,
    child: null,
  );
}
''';

    final fixedCall = await _applyFix(originalCall);
    expect(fixedCall, expectedCall);
  }

  Future<void> test_functionAndConstructorCallsSorted() async {
    await assertNoDiagnostics(r'''
void topLevel(int positional, {required int alpha, int beta = 0, String? charlie}) {}

class Example {
  final int alpha;
  final int beta;

  Example(int pos, {required this.alpha, this.beta = 0});
}

void caller() {
  topLevel(1, alpha: 1, beta: 2, charlie: 'c');
  final _ = Example(1, alpha: 10, beta: 20);
}
''');
  }

  Future<void> test_functionAndConstructorDeclarationsSorted() async {
    await assertNoDiagnostics(r'''
void topLevel(int positional, {required int alpha, int beta = 0, String? charlie}) {}

class Example {
  final int alpha;
  final int beta;

  Example(int pos, {required this.alpha, this.beta = 0, int? charlie});

  void method({int? alpha, required int beta}) {}
}
''');
  }

  Future<void> test_functionCallNamedArgumentsUnsorted() async {
    await assertDiagnostics(
      r'''
void foo({int? alpha, int? beta, int? charlie}) {}

void caller() {
  foo(charlie: 3, beta: 2, alpha: 1);
}
''',
      [lint(86, 4), lint(95, 5)],
    );
  }

  Future<void> test_functionDeclarationNamedParametersUnsorted() async {
    await assertDiagnostics(
      r'''
void topLevel(int pos, {required int beta, int alpha = 0}) {}
''',
      [lint(47, 5)],
    );
  }

  Future<void> test_ignoreOptionStillFlagsNonIgnoredUnsortedParameters() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

ilt_lints:
  sort_named_parameters:
    ignore:
      - key
      - child
''');

    await assertDiagnostics(
      r'''
class Widget {
  const Widget({String? key, int? beta, int? alpha, Widget? child});
}

Widget build() {
  return const Widget(
    key: 'k',
    beta: 2,
    alpha: 1,
    child: Widget(),
  );
}
''',
      [lint(60, 5), lint(158, 5)],
    );
  }

  Future<void> test_ignoreOptionViaAnalysisOptionsYaml() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

sort_named_parameters:
  ignore:
    - key
    - child
''');

    await assertNoDiagnostics(r'''
class Widget {
  const Widget({String? key, int? alpha, int? beta, Widget? child});
}

Widget build() {
  return const Widget(
    key: 'k',
    alpha: 1,
    beta: 2,
    child: Widget(),
  );
}
''');
  }

  Future<void> test_privateNamedParametersIgnoreLeadingUnderscore() async {
    await assertNoDiagnostics(r'''
class Example {
  final String _foo;
  final int elevation;
  final int galaxy;

  Example({
    required this.elevation,
    required this._foo,
    required this.galaxy,
  });

  Example.typed({
    required int this.elevation,
    required String this._foo,
    required int this.galaxy,
  });
}
''');
  }

  Future<void>
  test_privateNamedParametersUnsortedAndFixedIgnoringLeadingUnderscore() async {
    const original = r'''
class Example {
  final String _foo;
  final int elevation;
  final int galaxy;

  Example({
    required this._foo,
    required this.galaxy,
    required this.elevation,
  });
}
''';

    const expected = r'''
class Example {
  final String _foo;
  final int elevation;
  final int galaxy;

  Example({
    required this.elevation,
    required this._foo,
    required this.galaxy,
  });
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void>
  test_requiredFirstFixSortsRequiredThenOptionalPreservingIgnored() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

sort_named_parameters:
  required_first: true
  ignore:
    - key
    - child
''');

    const original = r'''
class Widget {
  const Widget({
    String? key,
    int? delta,
    required int zebra,
    int charlie = 0,
    required int beta,
    Widget? child,
  });
}
''';

    const expected = r'''
class Widget {
  const Widget({
    String? key,
    required int beta,
    required int zebra,
    int charlie = 0,
    int? delta,
    Widget? child,
  });
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void>
  test_requiredFirstFlagsRequiredAfterOptionalAndUnsortedGroups() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

sort_named_parameters:
  required_first: true
''');

    await assertDiagnostics(
      r'''
void foo({
  required int zebra,
  required int beta,
  int? delta,
  required int alpha,
  int? charlie,
}) {}
''',
      [lint(48, 4), lint(83, 5), lint(97, 7)],
    );
  }

  Future<void>
  test_requiredFirstValidInDeclarationAndCallSitePurelyAlphabetical() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - sort_named_parameters

sort_named_parameters:
  required_first: true
  ignore:
    - key
    - child
''');

    await assertNoDiagnostics(r'''
class Widget {
  const Widget({
    String? key,
    required int beta,
    required int zebra,
    int? alpha,
    int charlie = 0,
    Widget? child,
  });
}

Widget build() {
  return const Widget(
    key: 'k',
    alpha: 1,
    beta: 2,
    charlie: 3,
    zebra: 4,
    child: null,
  );
}
''');
  }

  Future<void> test_superParametersAndDefaultValuesUnsorted() async {
    await assertDiagnostics(
      r'''
class Base {
  Base({int? alpha, int? beta});
}

class Sub extends Base {
  Sub({super.beta, super.alpha});
}
''',
      [lint(99, 5)],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortNamedParameters.code)
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
    final producer = SortNamedParametersFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
