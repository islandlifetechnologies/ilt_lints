import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_functions_by_scope.dart';

/// A quick fix that reorders functions, getters, and setters within a type body
/// according to [FunctionScope].
class SortFunctionsByScopeFix extends ResolvedCorrectionProducer {
  SortFunctionsByScopeFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.sortFunctionsByScope',
    DartFixKindPriority.standard,
    'Sort functions by scope',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final body = node.thisOrAncestorMatching(
      (n) => n is BlockClassBody || n is BlockEnumBody,
    );
    final NodeList<ClassMember> members;
    if (body is BlockClassBody) {
      members = body.members;
    } else if (body is BlockEnumBody) {
      members = body.members;
    } else {
      return;
    }

    final entries = <_SortableMethod>[];
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      if (member is! MethodDeclaration) {
        continue;
      }
      final scope = FunctionScope.of(member);
      if (scope == null) {
        continue;
      }
      final memberRange = _rangeForMember(member);
      entries.add(
        _SortableMethod(
          originalOrder: entries.length,
          range: memberRange,
          scope: scope,
          text: utils.getRangeText(memberRange),
        ),
      );
    }

    if (entries.length < 2) {
      return;
    }

    final sorted = List<_SortableMethod>.of(entries)
      ..sort((a, b) {
        final cmp = a.scope.index.compareTo(b.scope.index);
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

class _SortableMethod {
  const _SortableMethod({
    required this.originalOrder,
    required this.range,
    required this.scope,
    required this.text,
  });

  final int originalOrder;
  final SourceRange range;
  final FunctionScope scope;
  final String text;
}
