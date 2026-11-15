// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ilt_lints/ilt_lints.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidLargeCcnTest);
  });
}

@reflectiveTest
class AvoidLargeCcnTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = AvoidLargeCcn();
    super.setUp();
  }

  Future<void> test_customCcnConfiguredInAnalysisOptions() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_large_ccn

avoid_large_ccn:
  ccn: 3
''');

    await assertDiagnostics(
      r'''
int withinLimit(int x) {
  if (x > 10) {
    return 10;
  } else if (x > 0) {
    return x;
  }
  return 0;
}

int exceedsLimit(int x) {
  if (x > 10 && x < 100) {
    return 10;
  } else if (x > 0) {
    return x;
  }
  return 0;
}
''',
      [lint(115, 12)],
    );
  }

  Future<void> test_customCcnConfiguredUnderPlugins() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_large_ccn

plugins:
  ilt_lints:
    diagnostics:
      avoid_large_ccn:
        ccn: 4
''');

    await assertDiagnostics(
      r'''
int complexControlFlow(int a, int? b) {
  var total = b ?? 0;
  for (var i = 0; i < a; i++) {
    if (i.isEven || i > 5) {
      total += i;
    }
  }
  return total;
}
''',
      [lint(4, 18)],
    );
  }

  Future<void> test_defaultCcnAllowsFunctionsUpToTwenty() async {
    await assertNoDiagnostics(r'''
int simpleFunction(int a, int b) {
  if (a > b) {
    return a;
  }
  return b;
}
''');
  }

  Future<void> test_defaultCcnFlagsFunctionExceedingTwenty() async {
    await assertDiagnostics(
      r'''
int overlyComplex(int x) {
  var r = 0;
  if (x == 1) r++;
  if (x == 2) r++;
  if (x == 3) r++;
  if (x == 4) r++;
  if (x == 5) r++;
  if (x == 6) r++;
  if (x == 7) r++;
  if (x == 8) r++;
  if (x == 9) r++;
  if (x == 10) r++;
  if (x == 11) r++;
  if (x == 12) r++;
  if (x == 13) r++;
  if (x == 14) r++;
  if (x == 15) r++;
  if (x == 16) r++;
  if (x == 17) r++;
  if (x == 18) r++;
  if (x == 19) r++;
  if (x == 20) r++;
  return r;
}
''',
      [lint(4, 13)],
    );
  }

  Future<void> test_methodAndSwitchComplexity() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_large_ccn

avoid_large_ccn:
  ccn: 3
''');

    await assertDiagnostics(
      r'''
class Evaluator {
  String evaluate(int value) {
    switch (value) {
      case 1:
        return 'one';
      case 2:
        return 'two';
      case 3:
        return 'three';
      default:
        return 'other';
    }
  }
}
''',
      [lint(27, 8)],
    );
  }

  Future<void> test_nestedFunctionEvaluatedIndependently() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_large_ccn

avoid_large_ccn:
  ccn: 2
''');

    await assertDiagnostics(
      r'''
int outer(int x) {
  int inner(int y) {
    if (y > 0 && y < 10) {
      return y;
    }
    return 0;
  }

  if (x > 0) {
    return inner(x);
  }
  return 0;
}
''',
      [lint(25, 5)],
    );
  }
}
