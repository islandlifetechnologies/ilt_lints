import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/valid_json_serializable.dart';

/// A quick fix that adds or updates `fromJson` and `toJson` methods for
/// `@JsonSerializable` classes.
class ValidJsonSerializableFix extends ResolvedCorrectionProducer {
  ValidJsonSerializableFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.validJsonSerializable',
    DartFixKindPriority.standard,
    'Add valid fromJson and/or toJson',
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

    final analysis = ValidJsonSerializable.analyzeClass(classNode);
    if (analysis == null || !analysis.hasIssues) {
      return;
    }

    final className = analysis.className;
    final eol = utils.endOfLine;
    final body = classNode.body;
    if (body is! BlockClassBody) {
      return;
    }

    // Determine indentation
    final classIndent = utils.getLinePrefix(classNode.offset);
    final memberIndent = '$classIndent  ';

    final fromJsonDeclaration = analysis.hasPrimaryConstructor
        ? 'factory fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);'
        : 'factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);';

    final toJsonDeclaration =
        'Map<String, dynamic> toJson() => _\$${className}ToJson(this);';

    final replacements = <ClassMember, String>{};
    final additions = <String>[];

    if (analysis.needsFromJson) {
      if (analysis.existingFromJson != null) {
        replacements[analysis.existingFromJson!] =
            '$memberIndent$fromJsonDeclaration';
      } else {
        additions.add('$memberIndent$fromJsonDeclaration');
      }
    }

    if (analysis.needsToJson) {
      if (analysis.existingToJson != null) {
        replacements[analysis.existingToJson!] =
            '$memberIndent$toJsonDeclaration';
      } else {
        additions.add('$memberIndent$toJsonDeclaration');
      }
    }

    await builder.addDartFileEdit(file, (builder) {
      for (final entry in replacements.entries) {
        builder.addSimpleReplacement(
          range.node(entry.key),
          entry.value,
        );
      }

      if (additions.isNotEmpty) {
        final rightBracket = body.rightBracket;
        // Insert right before rightBracket
        final insertion = '$eol${additions.join('$eol$eol')}$eol$classIndent';
        builder.addSimpleInsertion(rightBracket.offset, insertion);
      }
    });
  }
}
