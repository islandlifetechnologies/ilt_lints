import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_functions_by_scope.dart';

/// A quick fix that reorders functions, getters, and setters alphabetically
/// within each [FunctionScope] in a type body.
class SortFunctionsAlphabeticallyFix extends ResolvedCorrectionProducer {
  SortFunctionsAlphabeticallyFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.sortFunctionsAlphabetically',
    DartFixKindPriority.standard,
    'Sort functions alphabetically',
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

    final entriesByScope = <FunctionScope, List<_SortableMethod>>{};
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
      final scopeEntries = entriesByScope.putIfAbsent(scope, () => []);
      scopeEntries.add(
        _SortableMethod(
          name: member.name.lexeme,
          originalOrder: scopeEntries.length,
          range: memberRange,
          text: utils.getRangeText(memberRange),
        ),
      );
    }

    if (entriesByScope.isEmpty) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      for (final entries in entriesByScope.values) {
        if (entries.length < 2) {
          continue;
        }
        final sorted = List<_SortableMethod>.of(entries)
          ..sort((a, b) {
            final cmp = a.name.compareTo(b.name);
            if (cmp != 0) {
              return cmp;
            }
            return a.originalOrder.compareTo(b.originalOrder);
          });
        for (var i = 0; i < entries.length; i++) {
          final target = entries[i];
          final replacement = sorted[i];
          if (target.text != replacement.text) {
            builder.addSimpleReplacement(target.range, replacement.text);
          }
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
    required this.name,
    required this.originalOrder,
    required this.range,
    required this.text,
  });

  final String name;
  final int originalOrder;
  final SourceRange range;
  final String text;
}
