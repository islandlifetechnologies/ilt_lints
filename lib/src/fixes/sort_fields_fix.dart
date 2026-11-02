import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/sort_fields.dart';

/// A quick fix that moves fields above methods and sorts them by [FieldScope]
/// and alphabetically within each scope.
class SortFieldsFix extends ResolvedCorrectionProducer {
  SortFieldsFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.sortFields',
    DartFixKindPriority.standard,
    'Sort fields',
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

    final allSlots = <_MemberSlot>[];
    final fieldEntries = <_FieldEntry>[];
    final methodEntries = <_MemberSlot>[];

    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      if (member is FieldDeclaration) {
        final memberRange = _rangeForMember(member);
        final text = utils.getRangeText(memberRange);
        final slot = _MemberSlot(range: memberRange, text: text);
        allSlots.add(slot);
        fieldEntries.add(
          _FieldEntry(
            name: member.fields.variables.first.name.lexeme,
            originalOrder: fieldEntries.length,
            scope: FieldScope.of(member),
            slot: slot,
          ),
        );
      } else if (member is MethodDeclaration) {
        final memberRange = _rangeForMember(member);
        final text = utils.getRangeText(memberRange);
        final slot = _MemberSlot(range: memberRange, text: text);
        allSlots.add(slot);
        methodEntries.add(slot);
      }
    }

    if (fieldEntries.isEmpty) {
      return;
    }

    final sortedFields = List<_FieldEntry>.of(fieldEntries)
      ..sort((a, b) {
        final scopeCmp = a.scope.index.compareTo(b.scope.index);
        if (scopeCmp != 0) {
          return scopeCmp;
        }
        final nameCmp = a.name.compareTo(b.name);
        if (nameCmp != 0) {
          return nameCmp;
        }
        return a.originalOrder.compareTo(b.originalOrder);
      });

    final desiredSlots = <_MemberSlot>[
      for (final field in sortedFields) field.slot,
      ...methodEntries,
    ];

    await builder.addDartFileEdit(file, (builder) {
      for (var i = 0; i < allSlots.length; i++) {
        final target = allSlots[i];
        final replacement = desiredSlots[i];
        if (target.text != replacement.text) {
          builder.addSimpleReplacement(target.range, replacement.text);
        }
      }
    });
  }

  SourceRange _rangeForMember(ClassMember member) {
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

class _FieldEntry {
  const _FieldEntry({
    required this.name,
    required this.originalOrder,
    required this.scope,
    required this.slot,
  });

  final String name;
  final int originalOrder;
  final FieldScope scope;
  final _MemberSlot slot;
}

class _MemberSlot {
  const _MemberSlot({
    required this.range,
    required this.text,
  });

  final SourceRange range;
  final String text;
}

