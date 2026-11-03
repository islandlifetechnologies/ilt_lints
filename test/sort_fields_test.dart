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
    defineReflectiveTests(SortFieldsTest);
  });
}

@reflectiveTest
class SortFieldsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortFields();
    super.setUp();
  }

  Future<void> test_allFieldScopesAndAlphabeticalOrderValid() async {
    await assertNoDiagnostics(r'''
class Example {
  Example(this.alphaInstance, this._alphaPrivInstance);

  static const int alphaConst = 1;
  static const int betaConst = 2;

  static const int _alphaPrivConst = 1;
  static const int _betaPrivConst = 2;

  static final int alphaStatic = 1;
  static int betaStatic = 2;

  static final int _alphaPrivStatic = 1;
  static int _betaPrivStatic = 2;

  final int alphaInstance;
  int betaInstance = 0;

  final int _alphaPrivInstance;
  int _betaPrivInstance = 0;

  void someMethod() {}
}
''');
  }

  Future<void> test_alphabeticalOrderWithinScopes() async {
    await assertDiagnostics(
      r'''
class Example {
  static const int bConst = 1;
  static const int aConst = 2;

  static const int _bConst = 1;
  static const int _aConst = 2;

  static int bStatic = 1;
  static int aStatic = 2;

  static int _bStatic = 1;
  static int _aStatic = 2;

  final int bField = 1;
  final int aField = 2;

  final int _bField = 1;
  final int _aField = 2;
}
''',
      [
        lint(66, 6),
        lint(130, 7),
        lint(183, 7),
        lint(237, 8),
        lint(288, 6),
        lint(338, 7),
      ],
    );
  }

  Future<void> test_constructorsAllowedBeforeOrBetweenFields() async {
    await assertNoDiagnostics(r'''
class Example {
  static const int aConst = 1;

  Example(this.aField);

  final int aField;
  final int bField = 2;

  Example.named() : aField = 0;

  final int _privField = 3;

  int get getter => aField;
  void method() {}
}
''');
  }

  Future<void> test_enumAndMixinAndExtensionType() async {
    await assertDiagnostics(
      r'''
enum Status {
  active(1);
  const Status(this.value);
  final int zValue = 0;
  final int value;
}

mixin MyMixin {
  void foo() {}
  int bar = 0;
}
''',
      [
        lint(91, 5),
        lint(139, 3),
      ],
    );
  }

  Future<void> test_fieldAfterMethodGetterSetterOrOperator() async {
    await assertDiagnostics(
      r'''
class Example {
  void method() {}
  final int aField = 1;
}

class Example2 {
  int get getter => 1;
  final int aField = 1;
}

class Example3 {
  set setter(int v) {}
  final int aField = 1;
}

class Example4 {
  Example4 operator +(Example4 other) => this;
  final int aField = 1;
}
''',
      [
        lint(47, 6),
        lint(114, 6),
        lint(181, 6),
        lint(272, 6),
      ],
    );
  }

  Future<void> test_finalFirstDefaultTrueFixGroupsFinalAboveNonFinal() async {
    const original = r'''
class Example {
  int betaMutable = 1;
  final int zebraFinal = 2;
  int alphaMutable = 3;
  final int alphaFinal = 4;
}
''';

    const expected = r'''
class Example {
  final int alphaFinal = 4;
  final int zebraFinal = 2;
  int alphaMutable = 3;
  int betaMutable = 1;
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void>
      test_finalFirstDefaultTrueFlagsFinalAfterNonFinalInSameScope() async {
    await assertDiagnostics(
      r'''
class Example {
  static int alphaStatic = 1;
  static final int betaStatic = 2;

  int alphaInstance = 1;
  final int betaInstance = 2;
}
''',
      [
        lint(65, 10),
        lint(119, 12),
      ],
    );
  }

  Future<void> test_finalFirstDefaultTrueGroupsFinalAboveNonFinalValid() async {
    await assertNoDiagnostics(r'''
class Example {
  static final int zebraStatic = 1;
  static int alphaStatic = 2;

  static final int _zebraPrivStatic = 1;
  static int _alphaPrivStatic = 2;

  final int zebraInstance = 1;
  int alphaInstance = 2;

  final int _zebraPrivInstance = 1;
  int _alphaPrivInstance = 2;
}
''');
  }

  Future<void> test_finalFirstFalseFlagsUnsortedAndFixesAlphabetically() async {
    newAnalysisOptionsYamlFile(
      testPackageRootPath,
      '''
linter:
  rules:
    - sort_fields

sort_fields:
  final_first: false
''',
    );

    const original = r'''
class Example {
  final int zebraFinal = 1;
  int betaMutable = 2;
  final int alphaFinal = 3;
}
''';

    const expected = r'''
class Example {
  final int alphaFinal = 3;
  int betaMutable = 2;
  final int zebraFinal = 1;
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_finalFirstFalseSortsPurelyAlphabeticallyValid() async {
    newAnalysisOptionsYamlFile(
      testPackageRootPath,
      '''
linter:
  rules:
    - sort_fields

sort_fields:
  final_first: false
''',
    );

    await assertNoDiagnostics(r'''
class Example {
  int alphaInstance = 1;
  final int betaInstance = 2;
  int charlieInstance = 3;
}
''');
  }

  Future<void>
      test_fixMovesFieldsAboveMethodsAndSortsByScopeAndAlphabetically() async {
    const original = r'''
class Example {
  Example(this.alphaField, this.betaField);

  void firstMethod() {}

  final int betaField;

  /// Doc for alphaField
  final int alphaField;

  static int _privStatic = 1;

  static int betaStatic = 2;

  static int alphaStatic = 3;

  void secondMethod() {}

  final int _privField = 4;

  static const int _privConst = 5;

  static const int betaConst = 6;

  static const int alphaConst = 7;
}
''';

    const expected = r'''
class Example {
  Example(this.alphaField, this.betaField);

  static const int alphaConst = 7;

  static const int betaConst = 6;

  static const int _privConst = 5;

  static int alphaStatic = 3;

  static int betaStatic = 2;

  static int _privStatic = 1;

  /// Doc for alphaField
  final int alphaField;

  final int betaField;

  final int _privField = 4;

  void firstMethod() {}

  void secondMethod() {}
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_privateStaticAfterPublicInstance() async {
    await assertDiagnostics(
      r'''
class Example {
  final int pubField = 1;
  static int _privStatic = 2;
}
''',
      [
        lint(55, 11),
      ],
    );
  }

  Future<void> test_privateStaticConstAfterPublicStatic() async {
    await assertDiagnostics(
      r'''
class Example {
  static int pubStatic = 1;
  static const int _privConst = 2;
}
''',
      [
        lint(63, 10),
      ],
    );
  }

  Future<void> test_publicInstanceAfterPrivateInstance() async {
    await assertDiagnostics(
      r'''
class Example {
  final int _privField = 1;
  final int pubField = 2;
}
''',
      [
        lint(56, 8),
      ],
    );
  }

  Future<void> test_publicStaticAfterPrivateStatic() async {
    await assertDiagnostics(
      r'''
class Example {
  static int _privStatic = 1;
  static int pubStatic = 2;
}
''',
      [
        lint(59, 9),
      ],
    );
  }

  Future<void> test_publicStaticConstAfterPrivateStaticConst() async {
    await assertDiagnostics(
      r'''
class Example {
  static const int _privConst = 1;
  static const int pubConst = 2;
}
''',
      [
        lint(70, 8),
      ],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortFields.code)
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
    final producer = SortFieldsFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
