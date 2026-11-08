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
    defineReflectiveTests(UseClockTest);
  });
}

@reflectiveTest
class UseClockTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = UseClock();
    super.setUp();
  }

  Future<void> test_commentReferenceIgnored() async {
    await assertNoDiagnostics(r'''
/// Returns the current time instead of [DateTime.now].
int get answer => 42;
''');
  }

  Future<void> test_dateTimeNowCallInLibReported() async {
    await assertDiagnostics(
      r'''
DateTime currentTime() => DateTime.now();
''',
      [lint(26, 14)],
    );
  }

  Future<void> test_dateTimeNowInTestFolderIgnored() async {
    final testFolderFilePath = '$testPackageRootPath/test/my_test.dart';
    newFile(testFolderFilePath, r'''
DateTime currentTime() => DateTime.now();
final tearOff = DateTime.now;
''');

    await assertNoDiagnosticsInFile(testFolderFilePath);
  }

  Future<void> test_dateTimeNowTearOffInLibReported() async {
    await assertDiagnostics(
      r'''
final functions = {
  'now': DateTime.now,
};
''',
      [lint(29, 12)],
    );
  }

  Future<void> test_otherNowConstructorsAllowed() async {
    await assertNoDiagnostics(r'''
class CustomClock {
  CustomClock.now();
}

final custom = CustomClock.now();
final customTearOff = CustomClock.now;
''');
  }

  Future<void> test_quickFixDoesNotDuplicateExistingClockImport() async {
    const original = r'''
import 'package:clock/clock.dart';

DateTime currentTime() => DateTime.now();
''';

    final fixed = await _applyFix(original);
    expect(
      RegExp("import 'package:clock/clock.dart';").allMatches(fixed),
      hasLength(1),
    );
    expect(fixed, contains('DateTime currentTime() => clock.now();'));
  }

  Future<void> test_quickFixInsertsClockImportAlphabetically() async {
    const original = r'''
import 'dart:async';

import 'package:alpha/alpha.dart';
import 'package:zeta/zeta.dart';

DateTime currentTime() => DateTime.now();
''';

    const expected = r'''
import 'dart:async';

import 'package:alpha/alpha.dart';
import 'package:clock/clock.dart';
import 'package:zeta/zeta.dart';

DateTime currentTime() => clock.now();
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_quickFixReplacesDateTimeNowCallAndAddsImport() async {
    const original = r'''
DateTime currentTime() => DateTime.now();
''';

    const expected = r'''
import 'package:clock/clock.dart';

DateTime currentTime() => clock.now();
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_quickFixReplacesDateTimeNowTearOffAndAddsImport() async {
    const original = r'''
final functions = {
  'now': DateTime.now,
};
''';

    const expected = r'''
import 'package:clock/clock.dart';

final functions = {
  'now': clock.now,
};
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == UseClock.code)
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
    final producer = UseClockFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
