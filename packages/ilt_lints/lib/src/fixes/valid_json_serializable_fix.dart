import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/valid_json_serializable.dart';

/// A quick fix that adds the generated `part` directive and adds or updates
/// `fromJson` and `toJson` methods for `@JsonSerializable` classes.
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

    final analysis = ValidJsonSerializable.analyzeClass(
      classNode,
      filePath: file,
    );
    if (analysis == null || !analysis.hasIssues) {
      return;
    }

    final className = analysis.className;
    final eol = utils.endOfLine;
    final body = classNode.body;

    // Determine indentation
    final classIndent = utils.getLinePrefix(classNode.offset);
    final memberIndent = '$classIndent  ';

    final fromJsonDeclaration =
        'factory $className.fromJson(Map<String, dynamic> json) => ${analysis.fromJsonFunctionName}(json);';

    final toJsonDeclaration =
        'Map<String, dynamic> toJson() => ${analysis.toJsonFunctionName}(this);';

    final replacements = <ClassMember, String>{};
    final additions = <String>[];

    if (analysis.needsFromJson) {
      if (analysis.existingFromJson != null) {
        replacements[analysis.existingFromJson!] = fromJsonDeclaration;
      } else {
        additions.add('$memberIndent$fromJsonDeclaration');
      }
    }

    if (analysis.needsToJson) {
      if (analysis.existingToJson != null) {
        replacements[analysis.existingToJson!] = toJsonDeclaration;
      } else {
        additions.add('$memberIndent$toJsonDeclaration');
      }
    }

    final expectedPartUri = analysis.expectedPartUri;
    final alreadyAddedPart =
        expectedPartUri != null &&
        builder.sourceChange.edits.any(
          (fileEdit) =>
              fileEdit.file == file &&
              fileEdit.edits.any(
                (edit) => edit.replacement.contains("part '$expectedPartUri';"),
              ),
        );
    final partInsertion =
        (analysis.needsPartDirective &&
            expectedPartUri != null &&
            !alreadyAddedPart)
        ? _computePartDirectiveInsertion(unitResult.unit, expectedPartUri, eol)
        : null;

    if (partInsertion == null && replacements.isEmpty && additions.isEmpty) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      if (partInsertion != null) {
        final (offset, text) = partInsertion;
        builder.addSimpleInsertion(offset, text);
      }

      for (final entry in replacements.entries) {
        builder.addSimpleReplacement(range.node(entry.key), entry.value);
      }

      if (additions.isNotEmpty) {
        if (body is EmptyClassBody) {
          final replacement =
              ' {$eol${additions.join('$eol$eol')}$eol$classIndent}';
          builder.addSimpleReplacement(range.node(body), replacement);
        } else if (body is BlockClassBody) {
          if (body.members.isEmpty &&
              body.rightBracket.precedingComments == null) {
            final replacement =
                '{$eol${additions.join('$eol$eol')}$eol$classIndent}';
            builder.addSimpleReplacement(range.node(body), replacement);
          } else {
            final rightBracket = body.rightBracket;
            final insertion =
                '$eol${additions.join('$eol$eol')}$eol$classIndent';
            builder.addSimpleInsertion(rightBracket.offset, insertion);
          }
        }
      }
    });
  }

  (int, String)? _computePartDirectiveInsertion(
    CompilationUnit unit,
    String expectedPartUri,
    String eol,
  ) {
    if (unit.directives.any((d) => d is PartOfDirective)) {
      return null;
    }

    final partLine = "part '$expectedPartUri';";
    final existingParts = unit.directives.whereType<PartDirective>().toList();
    for (final directive in existingParts) {
      if (directive.uri.stringValue == expectedPartUri) {
        return null;
      }
    }

    if (existingParts.isNotEmpty) {
      for (final existing in existingParts) {
        final existingUri = existing.uri.stringValue;
        if (existingUri != null && existingUri.compareTo(expectedPartUri) > 0) {
          return (existing.offset, '$partLine$eol');
        }
      }
      final lastPart = existingParts.last;
      return (lastPart.end, '$eol$partLine');
    }

    if (unit.directives.isNotEmpty) {
      final lastDirective = unit.directives.last;
      return (lastDirective.end, '$eol$eol$partLine');
    }

    if (unit.declarations.isNotEmpty) {
      final firstDeclaration = unit.declarations.first;
      return (firstDeclaration.offset, '$partLine$eol$eol');
    }

    return (0, '$partLine$eol');
  }
}
