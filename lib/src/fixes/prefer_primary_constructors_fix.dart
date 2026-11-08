import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/prefer_primary_constructors.dart';

/// A quick fix that converts a [ClassDeclaration] to use a primary constructor.
class PreferPrimaryConstructorsFix extends ResolvedCorrectionProducer {
  PreferPrimaryConstructorsFix({required super.context});

  static const _fixKind = FixKind(
    'dart.fix.preferPrimaryConstructors',
    DartFixKindPriority.standard,
    'Convert to primary constructor',
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

    final analysis = PreferPrimaryConstructors.analyzeClass(classNode);
    if (analysis == null) {
      return;
    }

    final ctor = analysis.targetConstructor;
    if (ctor == null) {
      await builder.addDartFileEdit(file, (editBuilder) {
        editBuilder.addSimpleInsertion(classNode.namePart.end, '()');
      });
      return;
    }

    final body = classNode.body;
    if (body is! BlockClassBody) {
      return;
    }

    final eol = utils.endOfLine;
    final classIndent = utils.getLinePrefix(classNode.offset);

    final mergeableFieldsByName = <String, FieldDeclaration>{};
    if (analysis.hasSingleGenerativeConstructor) {
      for (final member in body.members) {
        if (member is! FieldDeclaration ||
            member.isStatic ||
            member.fields.isLate ||
            member.fields.variables.length != 1) {
          continue;
        }
        final variable = member.fields.variables.first;
        if (variable.initializer != null) {
          continue;
        }
        mergeableFieldsByName[variable.name.lexeme] = member;
      }
    }

    final mergedFields = <FieldDeclaration>{};
    final newParameterListText = _buildPrimaryParameterListText(
      ctor.parameters,
      eol: eol,
      mergeableFieldsByName: mergeableFieldsByName,
      mergedFieldsOut: mergedFields,
    );

    final ctorNameSuffix = ctor.name != null ? '.${ctor.name!.lexeme}' : '';
    final primaryBodyMemberText = _buildPrimaryConstructorBodyText(ctor);

    final removedMembers = <ClassMember>{
      ...mergedFields,
      if (primaryBodyMemberText == null) ctor,
    };

    await builder.addDartFileEdit(file, (editBuilder) {
      if (ctor.constKeyword != null) {
        editBuilder.addSimpleInsertion(classNode.classKeyword.end, ' const');
      }
      editBuilder.addSimpleInsertion(
        classNode.namePart.end,
        '$ctorNameSuffix$newParameterListText',
      );

      _applyBodyEdits(
        editBuilder,
        body: body,
        classIndent: classIndent,
        ctor: ctor,
        eol: eol,
        primaryBodyMemberText: primaryBodyMemberText,
        removedMembers: removedMembers,
      );
    });
  }

  void _applyBodyEdits(
    DartFileEditBuilder editBuilder, {
    required BlockClassBody body,
    required String classIndent,
    required ConstructorDeclaration ctor,
    required String eol,
    required String? primaryBodyMemberText,
    required Set<ClassMember> removedMembers,
  }) {
    final members = body.members;
    if (members.isNotEmpty && removedMembers.length == members.length) {
      editBuilder.addSimpleReplacement(range.node(body), '{}');
      return;
    }

    var index = 0;
    while (index < members.length) {
      final member = members[index];
      if (!removedMembers.contains(member)) {
        if (identical(member, ctor) && primaryBodyMemberText != null) {
          editBuilder.addSimpleReplacement(
            range.node(ctor),
            primaryBodyMemberText,
          );
        }
        index++;
        continue;
      }

      final runStart = index;
      while (index < members.length &&
          removedMembers.contains(members[index])) {
        index++;
      }
      if (index < members.length) {
        // Removed run is followed by a kept member at `members[index]`.
        final startOffset = _startOffsetWithLeadingComments(members[runStart]);
        final endOffset = _startOffsetWithLeadingComments(members[index]);
        editBuilder.addDeletion(
          range.startOffsetEndOffset(startOffset, endOffset),
        );
      } else {
        // Removed run reaches the end of `body.members`, preceded by a kept
        // member at `members[runStart - 1]`.
        final lastKept = members[runStart - 1];
        editBuilder.addSimpleReplacement(
          range.startOffsetEndOffset(lastKept.end, body.rightBracket.offset),
          '$eol$classIndent',
        );
      }
    }
  }

  String _buildDeclaringParameterText(
    FormalParameter param,
    FieldDeclaration fieldDecl, {
    required String eol,
    required bool isMultiline,
  }) {
    final match = _findThisFieldTokenRange(param);
    if (match == null) {
      return utils.getRangeText(range.node(param));
    }

    final (replaceStart, replaceEnd, explicitParamType) = match;
    final keyword = fieldDecl.fields.isFinal || fieldDecl.fields.isConst
        ? 'final'
        : 'var';
    final fieldTypeNode = fieldDecl.fields.type;
    final typeText = fieldTypeNode != null
        ? utils.getRangeText(range.node(fieldTypeNode))
        : explicitParamType;
    final declaringPrefix = typeText != null
        ? '$keyword $typeText '
        : '$keyword ';

    final paramStart = param.offset;
    final paramEnd = param.end;
    final beforeThis = utils.getRangeText(
      range.startOffsetEndOffset(paramStart, replaceStart),
    );
    final afterThis = utils.getRangeText(
      range.startOffsetEndOffset(replaceEnd, paramEnd),
    );

    final existingParamAnnotations = {
      for (final annotation in param.metadata)
        utils.getRangeText(range.node(annotation)),
    };
    final extraAnnotations = <String>[];
    for (final annotation in fieldDecl.metadata) {
      final text = utils.getRangeText(range.node(annotation));
      if (!existingParamAnnotations.contains(text)) {
        extraAnnotations.add(text);
      }
    }
    final annotationPrefix = extraAnnotations.isNotEmpty
        ? '${extraAnnotations.join(' ')} '
        : '';

    var docCommentPrefix = '';
    if (isMultiline && param.beginToken.precedingComments == null) {
      final fieldComments = _extractDocCommentLines(fieldDecl);
      if (fieldComments.isNotEmpty) {
        final paramIndent = utils.getLinePrefix(param.offset);
        docCommentPrefix =
            '${fieldComments.join('$eol$paramIndent')}$eol$paramIndent';
      }
    }

    return '$docCommentPrefix$annotationPrefix$beforeThis$declaringPrefix$afterThis';
  }

  String? _buildPrimaryConstructorBodyText(ConstructorDeclaration ctor) {
    final hasInitializers = ctor.initializers.isNotEmpty;
    final hasBody = _hasNonEmptyBody(ctor.body);
    if (!hasInitializers && !hasBody) {
      return null;
    }

    final initClause = hasInitializers
        ? ' : ${utils.getRangeText(range.startOffsetEndOffset(ctor.initializers.first.offset, ctor.initializers.last.end))}'
        : '';
    final bodyClause = hasBody
        ? ' ${utils.getRangeText(range.node(ctor.body))}'
        : ';';
    return 'this$initClause$bodyClause';
  }

  String _buildPrimaryParameterListText(
    FormalParameterList parameterList, {
    required String eol,
    required Map<String, FieldDeclaration> mergeableFieldsByName,
    required Set<FieldDeclaration> mergedFieldsOut,
  }) {
    final params = parameterList.parameters;
    if (params.isEmpty || mergeableFieldsByName.isEmpty) {
      return utils.getRangeText(range.node(parameterList));
    }

    final lineInfo = unitResult.lineInfo;
    final isMultiline =
        lineInfo.getLocation(parameterList.leftParenthesis.offset).lineNumber !=
        lineInfo.getLocation(parameterList.rightParenthesis.offset).lineNumber;

    final replacements = <(int, int, String)>[];
    for (final param in params) {
      final match = _findThisFieldTokenRange(param);
      if (match == null) {
        continue;
      }
      final paramName = param.name?.lexeme;
      if (paramName == null) {
        continue;
      }
      final fieldDecl = mergeableFieldsByName[paramName];
      if (fieldDecl == null) {
        continue;
      }
      mergedFieldsOut.add(fieldDecl);
      final newParamText = _buildDeclaringParameterText(
        param,
        fieldDecl,
        eol: eol,
        isMultiline: isMultiline,
      );
      replacements.add((param.offset, param.end, newParamText));
    }

    if (replacements.isEmpty) {
      return utils.getRangeText(range.node(parameterList));
    }

    final listStart = parameterList.offset;
    final listEnd = parameterList.end;
    final buffer = StringBuffer();
    var cursor = listStart;
    for (final (start, end, replacement) in replacements) {
      buffer.write(
        utils.getRangeText(range.startOffsetEndOffset(cursor, start)),
      );
      buffer.write(replacement);
      cursor = end;
    }
    buffer.write(
      utils.getRangeText(range.startOffsetEndOffset(cursor, listEnd)),
    );
    return buffer.toString();
  }

  List<String> _extractDocCommentLines(FieldDeclaration fieldDecl) {
    final lines = <String>[];
    Token? comment = fieldDecl.beginToken.precedingComments;
    while (comment != null) {
      final lexeme = comment.lexeme.trim();
      if (lexeme.startsWith('///') || lexeme.startsWith('/**')) {
        lines.add(lexeme);
      }
      comment = comment.next;
    }
    return lines;
  }

  (int, int, String?)? _findThisFieldTokenRange(FormalParameter param) {
    Token? token = param.beginToken;
    final endToken = param.endToken;

    Token? firstTypeOrThisToken;
    while (token != null) {
      if (token.type == TokenType.EQ || token.type == TokenType.COLON) {
        break;
      }
      if (token.type == Keyword.THIS && token.next?.type == TokenType.PERIOD) {
        final periodToken = token.next!;
        final nameToken = periodToken.next;
        if (nameToken == null) {
          return null;
        }
        final afterName = nameToken.next;
        if (afterName != null &&
            afterName.offset <= endToken.offset &&
            afterName.type == TokenType.OPEN_PAREN) {
          // Function-typed field formal parameter: leave untouched.
          return null;
        }
        final startOffset = (firstTypeOrThisToken ?? token).offset;
        String? explicitType;
        if (firstTypeOrThisToken != null &&
            firstTypeOrThisToken.offset < token.offset) {
          final rawPrefix = utils
              .getRangeText(
                range.startOffsetEndOffset(
                  firstTypeOrThisToken.offset,
                  token.offset,
                ),
              )
              .trim();
          if (rawPrefix != 'final' && rawPrefix != 'var') {
            explicitType = rawPrefix;
          }
        }
        return (startOffset, periodToken.end, explicitType);
      }

      final isMetadataToken = param.metadata.any(
        (m) => token!.offset >= m.offset && token.end <= m.end,
      );
      if (!isMetadataToken &&
          token.type != Keyword.REQUIRED &&
          token.type != Keyword.COVARIANT) {
        firstTypeOrThisToken ??= token;
      }

      if (identical(token, endToken)) {
        break;
      }
      token = token.next;
    }
    return null;
  }

  bool _hasNonEmptyBody(FunctionBody body) {
    if (body is EmptyFunctionBody) {
      return false;
    }
    if (body is BlockFunctionBody) {
      return body.block.statements.isNotEmpty ||
          body.block.rightBracket.precedingComments != null;
    }
    return true;
  }

  int _startOffsetWithLeadingComments(AstNode item) {
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
    return startOffset;
  }
}
