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
    defineReflectiveTests(SortFunctionsByScopeTest);
  });
}

@reflectiveTest
class SortFunctionsByScopeTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortFunctionsByScope();
    super.setUp();
  }

  Future<void> test_allScopesSortedCorrectly() async {
    await assertNoDiagnostics(r'''
class Example {
  static int get pubStaticGetter1 => 1;
  static int get pubStaticGetter2 => 2;

  static set pubStaticSetter1(int v) {}
  static set pubStaticSetter2(int v) {}

  static void pubStatic1() {}
  static void pubStatic2() {}

  static int get _privStaticGetter1 => 1;
  static int get _privStaticGetter2 => 2;

  static set _privStaticSetter1(int v) {}
  static set _privStaticSetter2(int v) {}

  static void _privStatic1() {}
  static void _privStatic2() {}

  int get pubGetter1 => 1;
  String get pubGetter2 => '';

  set pubSetter1(int v) {}
  set pubSetter2(String v) {}

  int get _privGetter1 => 1;
  String get _privGetter2 => '';

  set _privSetter1(int v) {}
  set _privSetter2(String v) {}

  void pubInstance1() {}
  void pubInstance2() {}

  void _privInstance1() {}
  void _privInstance2() {}
}
''');
  }

  Future<void> test_enumDeclaration() async {
    await assertDiagnostics(
      r'''
enum Status {
  active,
  inactive;

  void _privInstance() {}
  void pubInstance() {}
}
''',
      [lint(70, 11)],
    );
  }

  Future<void> test_extensionDeclaration() async {
    await assertDiagnostics(
      r'''
extension MyExt on String {
  void _privInstance() {}
  int get pubGetter => length;
}
''',
      [lint(64, 9)],
    );
  }

  Future<void> test_extensionTypeDeclaration() async {
    await assertDiagnostics(
      r'''
extension type Id(int value) {
  void pubInstance() {}
  static Id create() => Id(0);
}
''',
      [lint(67, 6)],
    );
  }

  Future<void>
  test_fixSortsAllScopesAndPreservesCommentsAndIgnoredMembers() async {
    const original = r'''
class Example {
  final int x;

  Example(this.x);

  /// Private instance doc
  void _privInstance() {}

  // Public instance comment
  @override
  String toString() => '$x';

  Example operator +(Example other) => Example(x + other.x);

  set _privSetter(int v) {}

  int get _privGetter => x;

  set pubSetter(int v) {}

  int get pubGetter => x;

  static void _privStatic() {}

  /// Public static doc
  static void pubStatic1() {}

  static void pubStatic2() {}
}
''';

    const expected = r'''
class Example {
  final int x;

  Example(this.x);

  /// Public static doc
  static void pubStatic1() {}

  static void pubStatic2() {}

  Example operator +(Example other) => Example(x + other.x);

  static void _privStatic() {}

  int get pubGetter => x;

  set pubSetter(int v) {}

  int get _privGetter => x;

  set _privSetter(int v) {}

  // Public instance comment
  @override
  String toString() => '$x';

  /// Private instance doc
  void _privInstance() {}
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_ignoresFieldsConstructorsAndOperators() async {
    await assertNoDiagnostics(r'''
class Example {
  final int a;
  Example(this.a);

  static void pubStatic() {}

  int b = 0;

  int get pubGetter => a + b;

  Example operator +(Example other) => Example(a + other.a);

  void pubInstance() {}

  Example.named() : a = 0;

  void _privInstance() {}

  @override
  bool operator ==(Object other) => identical(this, other);
}
''');
  }

  Future<void> test_mixinDeclaration() async {
    await assertDiagnostics(
      r'''
mixin MyMixin {
  void pubInstance() {}
  int get pubGetter => 1;
}
''',
      [lint(50, 9)],
    );
  }

  Future<void> test_privateGetterAfterPrivateSetter() async {
    await assertDiagnostics(
      r'''
class Example {
  set _privSetter(int v) {}
  int get _privGetter => 1;
}
''',
      [lint(54, 11)],
    );
  }

  Future<void> test_privateSetterAfterPublicInstance() async {
    await assertDiagnostics(
      r'''
class Example {
  void pubInstance() {}
  set _privSetter(int v) {}
}
''',
      [lint(46, 11)],
    );
  }

  Future<void> test_privateStaticAfterPublicGetter() async {
    await assertDiagnostics(
      r'''
class Example {
  int get pubGetter => 1;
  static void _privStatic() {}
}
''',
      [lint(56, 11)],
    );
  }

  Future<void> test_publicGetterAfterPublicSetter() async {
    await assertDiagnostics(
      r'''
class Example {
  set pubSetter(int v) {}
  int get pubGetter => 1;
}
''',
      [lint(52, 9)],
    );
  }

  Future<void> test_publicInstanceAfterPrivateInstance() async {
    await assertDiagnostics(
      r'''
class Example {
  void _privInstance() {}
  void pubInstance() {}
}
''',
      [lint(49, 11)],
    );
  }

  Future<void> test_publicSetterAfterPrivateGetter() async {
    await assertDiagnostics(
      r'''
class Example {
  int get _privGetter => 1;
  set pubSetter(int v) {}
}
''',
      [lint(50, 9)],
    );
  }

  Future<void> test_publicStaticAfterPrivateStatic() async {
    await assertDiagnostics(
      r'''
class Example {
  static void _privStatic() {}
  static void pubStatic() {}
}
''',
      [lint(61, 9)],
    );
  }

  Future<void>
  test_staticGetterAndSetterSubgroupedBeforeStaticFunctions() async {
    await assertDiagnostics(
      r'''
class Example {
  static void pubStatic() {}
  static set pubStaticSetter(int v) {}
  static int get pubStaticGetter => 1;
  static void _privStatic() {}
  static set _privStaticSetter(int v) {}
  static int get _privStaticGetter => 1;
}
''',
      [lint(58, 15), lint(101, 15), lint(167, 17), lint(212, 17)],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortFunctionsByScope.code)
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
    final producer = SortFunctionsByScopeFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
