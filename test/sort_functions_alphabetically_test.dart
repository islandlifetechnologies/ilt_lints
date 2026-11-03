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
    defineReflectiveTests(SortFunctionsAlphabeticallyTest);
  });
}

@reflectiveTest
class SortFunctionsAlphabeticallyTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortFunctionsAlphabetically();
    super.setUp();
  }

  Future<void> test_allScopesSortedAlphabetically() async {
    await assertNoDiagnostics(r'''
class Example {
  static int get alphaStaticGetter => 1;
  static int get betaStaticGetter => 2;

  static set alphaStaticSetter(int v) {}
  static set betaStaticSetter(int v) {}

  static void alphaStatic() {}
  static void betaStatic() {}

  static int get _alphaStaticGetter => 1;
  static int get _betaStaticGetter => 2;

  static set _alphaStaticSetter(int v) {}
  static set _betaStaticSetter(int v) {}

  static void _alphaStatic() {}
  static void _betaStatic() {}

  int get alphaGetter => 1;
  int get betaGetter => 2;

  set alphaSetter(int v) {}
  set betaSetter(int v) {}

  int get _alphaGetter => 1;
  int get _betaGetter => 2;

  set _alphaSetter(int v) {}
  set _betaSetter(int v) {}

  void alphaInstance() {}
  void betaInstance() {}

  void _alphaInstance() {}
  void _betaInstance() {}
}
''');
  }

  Future<void> test_enumMixinExtensionAndExtensionType() async {
    await assertDiagnostics(
      r'''
enum Status {
  active;
  void beta() {}
  void alpha() {}
}

mixin MyMixin {
  void beta() {}
  void alpha() {}
}

extension MyExt on String {
  void beta() {}
  void alpha() {}
}

extension type Id(int value) {
  void beta() {}
  void alpha() {}
}
''',
      [
        lint(48, 5),
        lint(102, 5),
        lint(168, 5),
        lint(237, 5),
      ],
    );
  }

  Future<void>
      test_fixSortsAlphabeticallyWithinEachScopeAndPreservesComments() async {
    const original = r'''
class Example {
  static void charlieStatic() {}

  /// Doc for alphaStatic
  static void alphaStatic() {}

  static void bravoStatic() {}

  int get zebraGetter => 1;

  int get alphaGetter => 2;

  // Comment on betaInstance
  void betaInstance() {}

  @override
  String toString() => '';

  void alphaInstance() {}

  void _zetaInstance() {}

  void _alphaInstance() {}
}
''';

    const expected = r'''
class Example {
  /// Doc for alphaStatic
  static void alphaStatic() {}

  static void bravoStatic() {}

  static void charlieStatic() {}

  int get alphaGetter => 2;

  int get zebraGetter => 1;

  void alphaInstance() {}

  // Comment on betaInstance
  void betaInstance() {}

  @override
  String toString() => '';

  void _alphaInstance() {}

  void _zetaInstance() {}
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_ignoresOperatorsFieldsAndConstructors() async {
    await assertNoDiagnostics(r'''
class Example {
  final int z;
  Example(this.z);
  Example.a() : z = 0;

  void alpha() {}
  Example operator +(Example other) => Example(z + other.z);
  Example operator -(Example other) => Example(z - other.z);
  void beta() {}
}
''');
  }

  Future<void> test_privateGettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  int get _beta => 1;
  int get _alpha => 2;
}
''',
      [
        lint(48, 6),
      ],
    );
  }

  Future<void> test_privateInstanceFunctionsOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  void _beta() {}
  void _alpha() {}
}
''',
      [
        lint(41, 6),
      ],
    );
  }

  Future<void> test_privateSettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  set _beta(int v) {}
  set _alpha(int v) {}
}
''',
      [
        lint(44, 6),
      ],
    );
  }

  Future<void> test_privateStaticFunctionsOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  static void _beta() {}
  static void _alpha() {}
}
''',
      [
        lint(55, 6),
      ],
    );
  }

  Future<void> test_publicGettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  int get beta => 1;
  int get alpha => 2;
}
''',
      [
        lint(47, 5),
      ],
    );
  }

  Future<void> test_publicInstanceFunctionsOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  void charlie() {}
  void bravo() {}
  void alpha() {}
}
''',
      [
        lint(43, 5),
        lint(61, 5),
      ],
    );
  }

  Future<void> test_publicSettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  set beta(int v) {}
  set alpha(int v) {}
}
''',
      [
        lint(43, 5),
      ],
    );
  }

  Future<void> test_publicStaticFunctionsOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  static void beta() {}
  static void alpha() {}
}
''',
      [
        lint(54, 5),
      ],
    );
  }

  Future<void> test_publicStaticGettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  static int get beta => 1;
  static int get alpha => 2;
}
''',
      [
        lint(61, 5),
      ],
    );
  }

  Future<void> test_publicStaticSettersOutOfAlphabeticalOrder() async {
    await assertDiagnostics(
      r'''
class Example {
  static set beta(int v) {}
  static set alpha(int v) {}
}
''',
      [
        lint(57, 5),
      ],
    );
  }

  Future<void>
      test_staticGettersSettersAndMethodsHaveSeparateAlphabeticalScopes() async {
    await assertNoDiagnostics(r'''
class Example {
  static int get zebraGetter => 1;
  static set middleSetter(int v) {}
  static void alphaMethod() {}
}
''');
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortFunctionsAlphabetically.code)
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
    final producer = SortFunctionsAlphabeticallyFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
