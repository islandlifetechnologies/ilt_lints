import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../rules/prefer_const_constructors.dart';

/// A quick fix that adds the `const` modifier to a class's primary constructor
/// (`class const Foo(...)`) or generative constructor declarations
/// (`const Foo(...);`).
class PreferConstConstructorsFix extends ResolvedCorrectionProducer {
  PreferConstConstructorsFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.preferConstConstructors',
    DartFixKindPriority.standard,
    'Add const modifier to constructor',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final classNode = node.thisOrAncestorOfType<ClassDeclaration>();
    if (classNode == null) {
      return;
    }

    final analysis = PreferConstConstructors.analyzeClass(classNode);
    if (analysis == null) {
      return;
    }

    await builder.addDartFileEdit(file, (editBuilder) {
      if (analysis.isPrimaryConstructor) {
        editBuilder.addSimpleInsertion(classNode.classKeyword.end, ' const');
      } else {
        for (final ctor in analysis.targetConstructors) {
          editBuilder.addSimpleInsertion(
            ctor.firstTokenAfterCommentAndMetadata.offset,
            'const ',
          );
        }
      }
    });
  }
}
