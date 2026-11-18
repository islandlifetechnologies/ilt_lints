import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'sort_functions_by_scope.dart';
import 'sort_widget_functions.dart';

/// A lint rule that enforces sorting functions, getters, and setters
/// alphabetically within each [FunctionScope].
class SortFunctionsAlphabetically({final bool? deferToSortWidgetFunctions})
    extends AnalysisRule {
  this
    : super(
        description: 'Sort functions, getters, and setters alphabetically within each scope.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'sort_functions_alphabetically',
    "Sort {0} alphabetically ('{1}' before '{2}').",
    correctionMessage:
        'Try sorting functions alphabetically within their scope.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    File? optionsFile;
    try {
      optionsFile = context
          .libraryElement
          ?.session
          .analysisContext
          .contextRoot
          .optionsFile;
    } on Object {
      optionsFile = null;
    }
    final deferWidgetFunctions =
        deferToSortWidgetFunctions ??
        SortWidgetFunctions.isRuleEnabled(
          context.definingUnit.file,
          optionsFile: optionsFile,
        );
    final visitor = _Visitor(this, deferWidgetFunctions: deferWidgetFunctions);
    registry.addBlockClassBody(this, visitor);
    registry.addBlockEnumBody(this, visitor);
  }
}

class const _Visitor(
  final SortFunctionsAlphabetically rule, {
  required final bool deferWidgetFunctions,
}) extends SimpleAstVisitor<void> {
  @override
  void visitBlockClassBody(BlockClassBody node) {
    final skipWidgetOwned =
        deferWidgetFunctions && SortWidgetFunctions.isWidgetClassBody(node);
    _checkMembers(node.members, skipWidgetOwned: skipWidgetOwned);
  }

  @override
  void visitBlockEnumBody(BlockEnumBody node) {
    _checkMembers(node.members, skipWidgetOwned: false);
  }

  void _checkMembers(
    NodeList<ClassMember> members, {
    required bool skipWidgetOwned,
  }) {
    final maxNameByScope = <FunctionScope, String>{};
    for (final member in members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      if (skipWidgetOwned && SortWidgetFunctions.isWidgetOwnedMethod(member)) {
        continue;
      }
      final scope = FunctionScope.of(member);
      if (scope == null) {
        continue;
      }
      final name = member.name.lexeme;
      final maxName = maxNameByScope[scope];
      if (maxName == null || name.compareTo(maxName) >= 0) {
        maxNameByScope[scope] = name;
      } else {
        rule.reportAtToken(
          member.name,
          arguments: [scope.description, name, maxName],
        );
      }
    }
  }
}
