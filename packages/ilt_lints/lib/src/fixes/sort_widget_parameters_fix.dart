import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_named_parameters.dart';
import '../rules/sort_widget_parameters.dart';

/// A quick fix that moves `child`, `children`, `builder` and `itemBuilder`
/// named parameters/arguments after all other named parameters, sorted
/// alphabetically, leaving the relative order of other items unchanged.
class SortWidgetParametersFix({required super.context})
    extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'dart.fix.sortWidgetParameters',
    DartFixKindPriority.standard,
    'Move widget child and builder parameters to the end',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final targetNode = node.thisOrAncestorMatching(
      (n) => n is FormalParameterList || n is ArgumentList,
    );
    if (targetNode == null) {
      return;
    }

    final entries = <_Item>[];
    if (targetNode is FormalParameterList) {
      for (final parameter in targetNode.parameters) {
        final nameToken = parameter.name;
        if (!parameter.isNamed || nameToken == null) {
          continue;
        }
        entries.add(_item(parameter, nameToken.lexeme));
      }
    } else if (targetNode is ArgumentList) {
      for (final argument in targetNode.arguments) {
        if (argument is NamedArgument) {
          entries.add(_item(argument, argument.name.lexeme));
        }
      }
    }
    if (entries.length < 2) {
      return;
    }

    final sorted = [
      ...entries.where((e) => !e.isTrailing),
      ...entries.where((e) => e.isTrailing).toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    ];

    await builder.addDartFileEdit(file, (builder) {
      for (var i = 0; i < entries.length; i++) {
        final target = entries[i];
        final replacement = sorted[i];
        if (target.text != replacement.text) {
          builder.addSimpleReplacement(target.range, replacement.text);
        }
      }
    });
  }

  _Item _item(AstNode node, String rawName) {
    final range = _rangeForItem(node);
    return _Item(
      isTrailing: SortWidgetParameters.isTrailingName(rawName),
      name: SortNamedParameters.normalizeParameterName(rawName),
      range: range,
      text: utils.getRangeText(range),
    );
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

class const _Item({
  required final bool isTrailing,
  required final String name,
  required final SourceRange range,
  required final String text,
}) {}
