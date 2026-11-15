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
    defineReflectiveTests(ExportLibraryTest);
  });
}

@reflectiveTest
class ExportLibraryTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ExportLibrary();
    super.setUp();
  }

  Future<void> test_customOptionsWithIncludeAndExcludeListsExcludeWins() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - export_library

export_library:
  - exporter: lib/custom_exporter.dart
    include:
      - feature/**/*.dart
      - extra/**/*.dart
    exclude:
      - feature/internal/**/*.dart
      - extra/secret.dart
''');

    newFile('$testPackageLibPath/feature/public_a.dart', 'class PublicA {}');
    newFile(
      '$testPackageLibPath/feature/sub/public_b.dart',
      'class PublicB {}',
    );
    newFile(
      '$testPackageLibPath/feature/internal/secret.dart',
      'class Secret {}',
    );
    newFile('$testPackageLibPath/extra/public_c.dart', 'class PublicC {}');
    newFile('$testPackageLibPath/extra/secret.dart', 'class ExtraSecret {}');

    final exporterPath = '$testPackageLibPath/custom_exporter.dart';
    const original = '''
export 'feature/public_a.dart';
''';
    newFile(exporterPath, original);

    final unitResult = await resolveFile(exporterPath);
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == ExportLibrary.code)
        .toList();
    expect(diagnostics, hasLength(1));

    final fixed = await _applyFixAtPath(exporterPath, original);
    expect(fixed, '''
export 'extra/public_c.dart';
export 'feature/public_a.dart';
export 'feature/sub/public_b.dart';
''');
  }

  Future<void> test_defaultExcludesGAndFreezedFiles() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');
    newFile('$testPackageLibPath/src/g.dart', 'class Generated {}');
    newFile('$testPackageLibPath/src/nested/freezed.dart', 'class Freezed {}');

    await assertNoDiagnostics('''
export 'src/alpha.dart';
''');
  }

  Future<void> test_defaultOptionsAllFilesExportedValid() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');
    newFile('$testPackageLibPath/src/nested/beta.dart', 'class Beta {}');

    await assertNoDiagnostics('''
export 'src/alpha.dart';
export 'src/nested/beta.dart';
''');
  }

  Future<void> test_defaultOptionsMissingExportsReported() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');
    newFile('$testPackageLibPath/src/beta.dart', 'class Beta {}');

    await assertDiagnostics(
      '''
export 'src/alpha.dart';
''',
      [lint(0, 25)],
    );
  }

  Future<void> test_defaultOptionsPackageUriExportRecognized() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');

    await assertNoDiagnostics('''
export 'package:test/src/alpha.dart';
''');
  }

  Future<void> test_fixInsertsAlphabeticallyAmongExistingExports() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');
    newFile('$testPackageLibPath/src/bravo.dart', 'class Bravo {}');
    newFile('$testPackageLibPath/src/charlie.dart', 'class Charlie {}');
    newFile('$testPackageLibPath/src/delta.dart', 'class Delta {}');

    const original = '''
export 'src/bravo.dart';
export 'src/delta.dart';
''';

    const expected = '''
export 'src/alpha.dart';
export 'src/bravo.dart';
export 'src/charlie.dart';
export 'src/delta.dart';
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_fixOnEmptyExporterFile() async {
    newFile('$testPackageLibPath/src/beta.dart', 'class Beta {}');
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');

    const original = '';
    const expected = '''
export 'src/alpha.dart';
export 'src/beta.dart';
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_fixOnExporterWithLibraryDirective() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');

    const original = '''
library;
''';

    const expected = '''
library;

export 'src/alpha.dart';
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_multipleExportersConfigured() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - export_library

export_library:
  - exporter: lib/first.dart
    include:
      - first/**/*.dart
  - exporter: lib/second.dart
    include:
      - second/**/*.dart
    exclude:
      - second/private_*.dart
''');

    newFile('$testPackageLibPath/first/a.dart', 'class A {}');
    newFile('$testPackageLibPath/second/b.dart', 'class B {}');
    newFile('$testPackageLibPath/second/private_c.dart', 'class PrivateC {}');

    final firstPath = '$testPackageLibPath/first.dart';
    final secondPath = '$testPackageLibPath/second.dart';

    const firstFixed = '''
export 'first/a.dart';
''';
    const secondFixed = '''
export 'second/b.dart';
''';

    expect(await _applyFixAtPath(firstPath, ''), firstFixed);
    expect(await _applyFixAtPath(secondPath, ''), secondFixed);
  }

  Future<void> test_nonExporterFileDoesNotReportDiagnostics() async {
    newFile('$testPackageLibPath/src/alpha.dart', 'class Alpha {}');
    final otherPath = '$testPackageLibPath/other.dart';
    newFile(otherPath, 'class Other {}');

    final unitResult = await resolveFile(otherPath);
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == ExportLibrary.code)
        .toList();
    expect(diagnostics, isEmpty);
  }

  Future<String> _applyFix(String content) =>
      _applyFixAtPath(testFile.path, content);

  Future<String> _applyFixAtPath(String filePath, String content) async {
    newFile(filePath, content);
    final unitResult = await resolveFile(filePath);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == ExportLibrary.code)
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
    final producer = ExportLibraryFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
