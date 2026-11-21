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
    defineReflectiveTests(PreferConstConstructorsTest);
  });
}

@reflectiveTest
class PreferConstConstructorsTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferConstConstructors();
    super.setUp();
  }

  Future<void> test_alreadyConst_primaryConstructor() async {
    await assertNoDiagnostics('''
class const User(final String name) {}
''');
  }

  Future<void> test_alreadyConst_standardConstructor() async {
    await assertNoDiagnostics('''
class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;
}
''');
  }

  Future<void> test_classWithConstFieldInitializer() async {
    const initial = '''
class Config() {
  final List<int> items = const [1, 2, 3];
}
''';
    const expected = '''
class const Config() {
  final List<int> items = const [1, 2, 3];
}
''';
    await assertDiagnostics(initial, [lint(6, 6)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_classWithConstSuperclass() async {
    const initial = '''
class const Base(final int id) {}

class Sub(final int id) extends Base {
  this : super(id);
}
''';
    const expected = '''
class const Base(final int id) {}

class const Sub(final int id) extends Base {
  this : super(id);
}
''';
    await assertDiagnostics(initial, [lint(41, 3)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_classWithConstructorBody_notReported() async {
    await assertNoDiagnostics('''
class Runner {
  Runner(this.name) {
    name.toString();
  }

  final String name;
}
''');
  }

  Future<void> test_classWithLateFinalField_notReported() async {
    await assertNoDiagnostics('''
class Lazy() {
  late final int value = 42;
}
''');
  }

  Future<void> test_classWithMutableDeclaringParameter_notReported() async {
    await assertNoDiagnostics('''
class Counter(var int count) {}
''');
  }

  Future<void> test_classWithMutableField_notReported() async {
    await assertNoDiagnostics('''
class Counter {
  Counter(this.count);

  int count;
}
''');
  }

  Future<void> test_classWithNonConstFieldInitializer_notReported() async {
    await assertNoDiagnostics('''
class Holder() {
  final List<int> items = [1, 2, 3];
}
''');
  }

  Future<void> test_classWithNonConstSuperclass_notReported() async {
    await assertNoDiagnostics('''
class Base(var int id) {}

class Sub() extends Base {
  this : super(0);
}
''');
  }

  Future<void> test_flexTableRowLikeWidget_notReported() async {
    await assertNoDiagnostics('''
import 'dart:math';

abstract class Key {
  const Key();
}

class ValueKey<T> extends Key {
  const ValueKey(this.value);
  final T value;
}

abstract class StatefulWidget {
  const StatefulWidget({this.key});
  final Key? key;
  Object createState();
}

class FlexTableRow({required final List<int> columns, Key? key}) {
  this : key = key ?? Random().nextDouble().toString();

  final Object key;
}

class Controller {}

class _FlexTableRow({
  required final Controller controller,
  required final FlexTableRow data,
  required final int index,
  required final bool selected,
}) extends StatefulWidget {
  this : super(key: ValueKey(data.key));

  @override
  Object createState() => Object();
}
''');
  }

  Future<void> test_generatedPartOfFile_notReported() async {
    newFile('$testPackageLibPath/main.dart', '''
part 'test.dart';
''');
    await assertNoDiagnostics('''
part of 'main.dart';

class Point {
  Point(this.x, this.y);

  final int x;
  final int y;
}

class User(final String name) {}
''');
  }

  Future<void> test_genericSuperArgumentUsingParameterProperty() async {
    await assertNoDiagnostics('''
class ValueKey<T> {
  const ValueKey(this.value);
  final T value;
}

class RowData {
  const RowData(this.key);
  final String key;
}

class Base {
  const Base({this.key});
  final ValueKey<String>? key;
}

class Row({
  required final RowData data,
  required final int index,
}) extends Base {
  this : super(key: ValueKey(data.key));
}
''');
  }

  Future<void> test_mutableFieldWithoutConstructor_notReported() async {
    await assertNoDiagnostics('''
class Foo {
  var items = <String>[];
}
''');
  }

  Future<void> test_primaryConstructor_canBeConst() async {
    const initial = '''
class User(final String name, {final int age = 0}) {}
''';
    const expected = '''
class const User(final String name, {final int age = 0}) {}
''';
    await assertDiagnostics(initial, [lint(6, 4)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_primaryConstructor_withConstBodyInitializers() async {
    const initial = '''
class Range(final int min, final int max) {
  this : assert(min <= max);
}
''';
    const expected = '''
class const Range(final int min, final int max) {
  this : assert(min <= max);
}
''';
    await assertDiagnostics(initial, [lint(6, 5)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_standardConstructor_canBeConst() async {
    const initial = '''
class Point {
  Point(this.x, this.y);

  final int x;
  final int y;
}
''';
    const expected = '''
class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;
}
''';
    await assertDiagnostics(initial, [lint(6, 5)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_standardConstructor_multipleWithRedirect() async {
    const initial = '''
class Point {
  Point(this.x, this.y);
  Point.origin() : this(0, 0);

  final int x;
  final int y;
}
''';
    const expected = '''
class Point {
  const Point(this.x, this.y);
  const Point.origin() : this(0, 0);

  final int x;
  final int y;
}
''';
    await assertDiagnostics(initial, [lint(6, 5)]);
    final fixed = await _applyFix(initial);
    expect(fixed, expected);
  }

  Future<void> test_superArgumentUsingParameterProperty_notReported() async {
    await assertNoDiagnostics('''
class Key {
  const Key(this.value);
  final String value;
}

class Base {
  const Base({this.key});
  final Key? key;
}

class Row({
  required final MapEntry<String, String> data,
}) extends Base {
  this : super(key: Key(data.key));
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
        .where((d) => d.diagnosticCode == PreferConstConstructors.code)
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
    final producer = PreferConstConstructorsFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
