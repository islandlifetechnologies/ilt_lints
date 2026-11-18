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
    defineReflectiveTests(SortWidgetFunctionsTest);
  });
}

@reflectiveTest
class SortWidgetFunctionsTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortWidgetFunctions();
    super.setUp();
  }

  Future<void> test_allWidgetCategoriesSortedCorrectly() async {
    await assertNoDiagnostics(r'''
abstract class Widget {}
abstract class StatelessWidget extends Widget {}

class MyWidget extends StatelessWidget {
  void initState() {}

  void didChangeDependencies() {}

  void didUpdateWidget() {}

  void deactivate() {}

  void dispose() {}

  static void staticHelper() {}

  int get someGetter => 1;

  void regularHelper() {}

  void _privateHelper() {}

  void buildHeader() {}

  void buildFooter() {}

  void _buildRow() {}

  void _buildItem() {}

  void build() {}
}
''');
  }

  Future<void> test_buildBeforeBuildPrefixedAndDispose() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}

class MyWidget extends Widget {
  void build() {}
  void dispose() {}
  void buildHeader() {}
  void _buildFooter() {}
}
''',
      [lint(83, 7), lint(103, 11), lint(127, 12)],
    );
  }

  Future<void> test_customWidgetSubclassHierarchy() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}
abstract class CustomBaseWidget extends Widget {}

class MyScreen extends CustomBaseWidget {
  void build() {}
  void initState() {}
}
''',
      [lint(143, 9)],
    );
  }

  Future<void> test_fixSortsWidgetFunctionsAndPreservesComments() async {
    const original = r'''
abstract class Widget {}
abstract class StatefulWidget extends Widget {}

class MyWidget extends StatefulWidget {
  final int count = 0;

  /// Main build method
  void build() {}

  void _buildPrivateB() {}

  void _buildPrivateA() {}

  void buildPublicB() {}

  void buildPublicA() {}

  void _regularPrivate() {}

  void regularPublic() {}

  int get countGetter => count;

  void dispose() {}

  void deactivate() {}

  void didUpdateWidget() {}

  void didChangeDependencies() {}

  /// Init state doc
  void initState() {}
}
''';

    const expected = r'''
abstract class Widget {}
abstract class StatefulWidget extends Widget {}

class MyWidget extends StatefulWidget {
  final int count = 0;

  /// Init state doc
  void initState() {}

  void didChangeDependencies() {}

  void didUpdateWidget() {}

  void deactivate() {}

  void dispose() {}

  void _regularPrivate() {}

  void regularPublic() {}

  int get countGetter => count;

  void buildPublicB() {}

  void buildPublicA() {}

  void _buildPrivateB() {}

  void _buildPrivateA() {}

  /// Main build method
  void build() {}
}
''';

    final fixed = await _applyFix(original);
    expect(fixed, expected);
  }

  Future<void> test_lifecycleFunctionsOutOfOrder() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}
abstract class StatelessWidget extends Widget {}

class MyWidget extends StatelessWidget {
  void dispose() {}
  void deactivate() {}
  void didUpdateWidget() {}
  void didChangeDependencies() {}
  void initState() {}
}
''',
      [lint(143, 10), lint(166, 15), lint(194, 21), lint(228, 9)],
    );
  }

  Future<void>
  test_nonWidgetClassPassesEvenWithReversedLifecycleAndBuild() async {
    await assertNoDiagnostics(r'''
class NotAWidget {
  void build() {}
  void _buildHelper() {}
  void buildHelper() {}
  void dispose() {}
  void deactivate() {}
  void didUpdateWidget() {}
  void didChangeDependencies() {}
  void initState() {}
}
''');
  }

  Future<void> test_privateBuildPrefixBeforePublicBuildPrefix() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}

class MyWidget extends Widget {
  void _buildPrivate() {}
  void buildPublic() {}
  void build() {}
}
''',
      [lint(91, 11)],
    );
  }

  Future<void> test_regularFunctionAfterBuildPrefix() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}

class MyWidget extends Widget {
  void initState() {}
  void buildHeader() {}
  void regularHelper() {}
  void build() {}
}
''',
      [lint(111, 13)],
    );
  }

  Future<void> test_regularFunctionBeforeLifecycleMethods() async {
    await assertDiagnostics(
      r'''
abstract class Widget {}

class MyWidget extends Widget {
  void regularHelper() {}
  void initState() {}
  void dispose() {}
  void build() {}
}
''',
      [lint(91, 9), lint(113, 7)],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortWidgetFunctions.code)
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
    final producer = SortWidgetFunctionsFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
