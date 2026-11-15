import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// A quick fix that converts all parameters in a [FormalParameterList] to
/// named parameters.
class PreferNamedParametersFix({required super.context})
    extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'dart.fix.preferNamedParameters',
    DartFixKindPriority.standard,
    'Convert to named parameters',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final targetNode = node.thisOrAncestorOfType<FormalParameterList>();
    if (targetNode == null || targetNode.parameters.isEmpty) {
      return;
    }

    final convertedParams = [
      for (final parameter in targetNode.parameters)
        _convertParameterText(parameter),
    ];

    final lineInfo = unitResult.lineInfo;
    final isMultiline =
        lineInfo.getLocation(targetNode.leftParenthesis.offset).lineNumber !=
        lineInfo.getLocation(targetNode.rightParenthesis.offset).lineNumber;

    final tokenAfterLast = targetNode.parameters.last.endToken.next;
    final hasTrailingComma =
        tokenAfterLast != null && tokenAfterLast.type == TokenType.COMMA;

    final String replacement;
    if (isMultiline) {
      final eol = utils.endOfLine;
      final firstParamRange = _rangeForItem(targetNode.parameters.first);
      final paramIndent = utils.getLinePrefix(firstParamRange.offset);
      final closingIndent = utils.getLinePrefix(
        targetNode.rightParenthesis.offset,
      );
      final trailingComma = hasTrailingComma ? ',' : '';
      final joined = convertedParams
          .map((param) => '$paramIndent$param')
          .join(',$eol');
      replacement = '{$eol$joined$trailingComma$eol$closingIndent}';
    } else {
      final trailingComma = hasTrailingComma ? ',' : '';
      replacement = '{${convertedParams.join(', ')}$trailingComma}';
    }

    final replaceRange = range.startOffsetEndOffset(
      targetNode.leftParenthesis.end,
      targetNode.rightParenthesis.offset,
    );

    await builder.addDartFileEdit(file, (editBuilder) {
      editBuilder.addSimpleReplacement(replaceRange, replacement);
    });
  }

  String _convertParameterText(FormalParameter parameter) {
    final itemRange = _rangeForItem(parameter);
    final needsRequired =
        parameter.isRequiredPositional ||
        (parameter.isOptionalPositional &&
            !_hasDefaultValue(parameter) &&
            !_isNullableParameter(parameter));

    if (!needsRequired) {
      return utils.getRangeText(itemRange);
    }

    final insertOffset = parameter.metadata.isNotEmpty
        ? parameter.metadata.last.endToken.next!.offset
        : parameter.offset;
    final before = utils.getRangeText(
      range.startOffsetEndOffset(itemRange.offset, insertOffset),
    );
    final after = utils.getRangeText(
      range.startOffsetEndOffset(insertOffset, itemRange.end),
    );
    return '${before}required $after';
  }

  bool _hasDefaultValue(FormalParameter parameter) =>
      parameter.defaultClause?.value != null;

  bool _isNullableParameter(FormalParameter parameter) {
    final elementType = parameter.declaredFragment?.element.type;
    if (elementType != null &&
        elementType.nullabilitySuffix == NullabilitySuffix.question) {
      return true;
    }
    return parameter.name?.previous?.type == TokenType.QUESTION;
  }

  SourceRange _rangeForItem(AstNode item) {
    final lineInfo = unitResult.lineInfo;
    final beginToken = item.beginToken;
    final previousToken = beginToken.previous;
    final prevEndLine = previousToken != null
        ? lineInfo.getLocation(previousToken.end).lineNumber
        : 0;

    var startOffset = item.offset;
    Token? comment = beginToken.precedingComments;
    while (comment != null) {
      final commentLine = lineInfo.getLocation(comment.offset).lineNumber;
      if (commentLine > prevEndLine) {
        startOffset = comment.offset;
        break;
      }
      comment = comment.next;
    }

    return range.startOffsetEndOffset(startOffset, item.end);
  }
}
