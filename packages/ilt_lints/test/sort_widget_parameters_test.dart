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
    defineReflectiveTests(SortWidgetParametersTest);
  });
}

@reflectiveTest
class SortWidgetParametersTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SortWidgetParameters();
    super.setUp();
  }

  Future<void> test_childBeforeOtherParameters() async {
    await assertDiagnostics(
      r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({Widget? child, int? alpha});
}
''',
      [lint(69, 5)],
    );
  }

  Future<void> test_fixMovesTrailingParametersLastAlphabetically() async {
    final result = await _applyFix(r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({
    Widget? itemBuilder,
    int? zed,
    Widget? child,
    int? alpha,
    Widget? builder,
  });
}
''');
    expect(result, r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({
    int? zed,
    int? alpha,
    Widget? builder,
    Widget? child,
    Widget? itemBuilder,
  });
}
''');
  }

  Future<void> test_nonWidgetClassNotReported() async {
    await assertNoDiagnostics(r'''
class Example {
  Example({Object? child, int? alpha});
}
''');
  }

  Future<void> test_sortedTrailingParametersNotReported() async {
    await assertNoDiagnostics(r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({int? alpha, int? zed, Widget? builder, Widget? child});
}
''');
  }

  Future<void> test_takesPriorityOverSortNamedParameters() async {
    // sort_named_parameters must not report the trailing names in widgets.
    rule = SortNamedParameters();
    await assertNoDiagnostics(r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({int? alpha, int? zed, Widget? child});
}
''');
    await assertNoDiagnostics(r'''
class Widget {}

class MyWidget2 extends Widget {
  MyWidget2({Widget? child, int? alpha});
}
''');
  }

  Future<void> test_trailingParametersOutOfOrder() async {
    await assertDiagnostics(
      r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({int? alpha, Widget? child, Widget? builder});
}
''',
      [lint(96, 7)],
    );
  }

  Future<void> test_widgetCallSite() async {
    await assertDiagnostics(
      r'''
class Widget {}

class MyWidget extends Widget {
  MyWidget({Widget? child, int? alpha});
}

void f() {
  MyWidget(child: null, alpha: 1);
}
''',
      [lint(69, 5), lint(115, 5)],
    );
  }

  Future<String> _applyFix(String content) async {
    newFile(testFile.path, content);
    final unitResult = await resolveFile(testFile.path);
    final libraryResult = await unitResult.session.getResolvedLibraryByElement(
      unitResult.libraryElement,
    ) as ResolvedLibraryResult;
    final diagnostics = unitResult.diagnostics
        .where((d) => d.diagnosticCode == SortWidgetParameters.code)
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
    final producer = SortWidgetParametersFix(context: context);
    final builder = ChangeBuilder(session: unitResult.session);
    await producer.compute(builder);
    final fileEdits = builder.sourceChange.edits;
    expect(fileEdits, hasLength(1));
    return SourceEdit.applySequence(content, fileEdits.first.edits);
  }
}
