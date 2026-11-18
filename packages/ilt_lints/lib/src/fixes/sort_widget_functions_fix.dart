import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_widget_functions.dart';

/// A quick fix that reorders widget lifecycle and build functions within a
/// Widget class body according to [WidgetFunctionCategory].
class SortWidgetFunctionsFix({required super.context})
    extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'dart.fix.sortWidgetFunctions',
    DartFixKindPriority.standard,
    'Sort widget functions',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final classNode = node.thisOrAncestorOfType<ClassDeclaration>();
    if (classNode == null || !SortWidgetFunctions.isWidgetClass(classNode)) {
      return;
    }
    final body = classNode.body;
    if (body is! BlockClassBody) {
      return;
    }
    final members = body.members;

    final entries = <_SortableWidgetMethod>[];
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      if (member is! MethodDeclaration) {
        continue;
      }
      final category = WidgetFunctionCategory.of(member);
      if (category == null) {
        continue;
      }
      final memberRange = _rangeForMember(member);
      entries.add(
        _SortableWidgetMethod(
          category: category,
          originalOrder: entries.length,
          range: memberRange,
          text: utils.getRangeText(memberRange),
        ),
      );
    }

    if (entries.length < 2) {
      return;
    }

    final sorted = List<_SortableWidgetMethod>.of(entries)
      ..sort((a, b) {
        final cmp = a.category.index.compareTo(b.category.index);
        if (cmp != 0) {
          return cmp;
        }
        return a.originalOrder.compareTo(b.originalOrder);
      });

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

  SourceRange _rangeForMember(MethodDeclaration member) {
    final lineInfo = unitResult.lineInfo;
    final beginToken = member.beginToken;
    final previousToken = beginToken.previous;
    final prevEndLine = previousToken != null
        ? lineInfo.getLocation(previousToken.end).lineNumber
        : 0;

    var startOffset = member.offset;
    Token? comment = beginToken.precedingComments;
    while (comment != null) {
      final commentLine = lineInfo.getLocation(comment.offset).lineNumber;
      if (commentLine > prevEndLine) {
        startOffset = comment.offset;
        break;
      }
      comment = comment.next;
    }

    var endOffset = member.end;
    final endToken = member.endToken;
    final nextToken = endToken.next;
    if (nextToken != null) {
      final endLine = lineInfo.getLocation(endOffset).lineNumber;
      final trailingComment = nextToken.precedingComments;
      if (trailingComment != null &&
          lineInfo.getLocation(trailingComment.offset).lineNumber == endLine) {
        endOffset = trailingComment.end;
      }
    }

    return range.startOffsetEndOffset(startOffset, endOffset);
  }
}

class const _SortableWidgetMethod({
  required final WidgetFunctionCategory category,
  required final int originalOrder,
  required final SourceRange range,
  required final String text,
}) {}
