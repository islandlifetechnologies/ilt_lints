// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ilt_lints/ilt_lints.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseFileSystemTest);
  });
}

@reflectiveTest
class UseFileSystemTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = UseFileSystem();
    super.setUp();
  }

  Future<void> test_dartIoInLibReported() async {
    await assertDiagnostics(
      r'''
import 'dart:io';

File openFile(String path) => File(path);
''',
      [lint(19, 4), lint(49, 10)],
    );
  }

  Future<void> test_dartIoInTestFolderIgnored() async {
    final testFolderFilePath = '$testPackageRootPath/test/my_io_test.dart';
    newFile(testFolderFilePath, r'''
import 'dart:io';

File openFile(String path) => File(path);
''');

    await assertNoDiagnosticsInFile(testFolderFilePath);
  }

  Future<void> test_directorySystemTempChainedReported() async {
    await assertDiagnostics(
      r'''
import 'dart:io';

Future<String> makeTemp() async {
  final dir = await Directory.systemTemp.createTemp('x');
  return dir.path;
}
''',
      [lint(73, 20), error(diag.undefinedStaticMemberReadNotFound, 83, 10)],
    );
  }

  Future<void> test_directorySystemTempReported() async {
    await assertDiagnostics(
      r'''
import 'dart:io';

String tempPath() => Directory.systemTemp.path;
''',
      [lint(40, 20), error(diag.undefinedStaticMemberReadNotFound, 50, 10)],
    );
  }

  Future<void> test_quickFixChainedSystemTemp() async {
    const original = r'''
import 'dart:io';

Future<String> makeTemp() async {
  final dir = await Directory.systemTemp.createTemp('x');
  return dir.path;
}
''';

    const expected = r'''
import 'package:io_ext/io_ext.dart';

Future<String> makeTemp() async {
  final dir = await fs.systemTempDirectory.createTemp('x');
  return dir.path;
}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_quickFixClassWithPrimaryConstructor() async {
    const original = r'''
import 'dart:io';

class PersistenceRepository({
  required final Directory root,
}) {
  void delete(String id) {
    final file = File('${root.path}/$id.yaml');
    final dir = Directory(root.path);
  }
}
''';

    const expected = r'''
import 'package:file/file.dart';
import 'package:io_ext/io_ext.dart';

class PersistenceRepository({
  required final Directory root,
}) {
  void delete(String id) {
    final file = fs.file('${root.path}/$id.yaml');
    final dir = fs.directory(root.path);
  }
}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_quickFixHidesDartIoWhenOtherSymbolsUsed() async {
    const original = r'''
import 'dart:io';

void logAndRead(String path) {
  stdout.writeln(path);
  final file = File(path);
}
''';

    const expected = r'''
import 'dart:io' hide Directory, File, FileSystemEntity, Link;

import 'package:io_ext/io_ext.dart';

void logAndRead(String path) {
  stdout.writeln(path);
  final file = fs.file(path);
}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_quickFixKeepsExistingIoExtImport() async {
    const original = r'''
import 'dart:io';

import 'package:io_ext/io_ext.dart';

class MyService {
  void run(String path) {
    final file = File(path);
    final dir = Directory.systemTemp;
  }
}
''';

    const expected = r'''
import 'package:io_ext/io_ext.dart';

class MyService {
  void run(String path) {
    final file = fs.file(path);
    final dir = fs.systemTempDirectory;
  }
}
''';

    expect(await _applyFix(original), expected);
  }

  Future<void> test_quickFixTopLevelFunction() async {
    const original = r'''
import 'dart:io';

File loadConfig(String path, {required bool create}) {
  final dir = Directory.current;
  return File('${dir.path}/$path');
}
''';

    const expected = r'''
import 'package:file/file.dart';
import 'package:io_ext/io_ext.dart';

File loadConfig(String path, {required bool create}) {
  final dir = fs.currentDirectory;
  return fs.file('${dir.path}/$path');
}
''';

    expect(await _applyFix(original), expected);
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == UseFileSystem.code)
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
    final producer = UseFileSystemFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
