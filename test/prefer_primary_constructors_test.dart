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
    defineReflectiveTests(PreferPrimaryConstructorsTest);
  });
}

@reflectiveTest
class PreferPrimaryConstructorsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferPrimaryConstructors();
    super.setUp();
  }

  Future<void> test_alreadyUsingPrimaryConstructorNoDiagnostic() async {
    await assertNoDiagnostics(r'''
class User(final String name) {}
''');
  }

  Future<void> test_classWithoutPrimaryConstructorReported() async {
    await assertDiagnostics(
      r'''
class User {
  final String name;

  User(this.name);
}
''',
      [lint(6, 4)],
    );
  }

  Future<void> test_generatedPartOfFile_notReported() async {
    newFile('$testPackageLibPath/main.dart', '''
part 'test.dart';
''');
    await assertNoDiagnostics(r'''
part of 'main.dart';

class User {
  final String name;

  User(this.name);
}
''');
  }

  Future<void> test_quickFixClassWithConstAndNamedParameters() async {
    const original = r'''
class BaseWidget {
  const BaseWidget({this.key});
  final String? key;
}

class MyWidget extends BaseWidget {
  const MyWidget({
    super.key,
    this.title = 'Hello',
    required this.count,
  });

  final int count;
  final String title;

  int get doubled => count * 2;
}
''';

    const expected = r'''
class BaseWidget {
  const BaseWidget({this.key});
  final String? key;
}

class const MyWidget({
    super.key,
    final String title = 'Hello',
    required final int count,
  }) extends BaseWidget {
  int get doubled => count * 2;
}
''';

    final fixed = await _applyFixAtIndex(original, 1);
    expect(fixed, expected);
  }

  Future<void> test_quickFixClassWithInitializerList() async {
    const original = r'''
class LoggingService {
  LoggingService({
    String? loggerName,
    this.level = 1,
  }) : loggerName = loggerName ?? 'root';

  final int level;
  final String loggerName;
}
''';

    const expected = r'''
class LoggingService({
    String? loggerName,
    final int level = 1,
  }) {
  this : loggerName = loggerName ?? 'root';

  final String loggerName;
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_quickFixClassWithNamedPrivateConstructor() async {
    const original = r'''
class DateTimeFunctions {
  const DateTimeFunctions._();

  static const version = 1;
}
''';

    const expected = r'''
class const DateTimeFunctions._() {
  static const version = 1;
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_quickFixClassWithNoConstructorsAddsParentheses() async {
    const original = r'''
class EmptyService {
  void run() {}
}
''';

    const expected = r'''
class EmptyService() {
  void run() {}
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void>
  test_quickFixSimpleClassMergesFieldAndRemovesConstructor() async {
    const original = r'''
class User {
  final String name;

  User(this.name);
}
''';

    const expected = r'''
class User(final String name) {}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<String> _applyFix(String content) => _applyFixAtIndex(content, 0);

  Future<String> _applyFixAtIndex(String content, int index) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == PreferPrimaryConstructors.code)
        .toList();
    expect(diagnostics.length, greaterThan(index));

    final diagnostic = diagnostics[index];
    final context = CorrectionProducerContext.createResolved(
      diagnostic: diagnostic,
      libraryResult: libraryResult,
      selectionLength: diagnostic.length,
      selectionOffset: diagnostic.offset,
      unitResult: unitResult,
    );
    final producer = PreferPrimaryConstructorsFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
