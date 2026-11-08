import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'sort_functions_by_scope.dart';

/// A lint rule that enforces sorting functions, getters, and setters
/// alphabetically within each [FunctionScope].
class SortFunctionsAlphabetically extends AnalysisRule {
  SortFunctionsAlphabetically()
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
    final visitor = _Visitor(this);
    registry.addBlockClassBody(this, visitor);
    registry.addBlockEnumBody(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final SortFunctionsAlphabetically rule;

  @override
  void visitBlockClassBody(BlockClassBody node) {
    _checkMembers(node.members);
  }

  @override
  void visitBlockEnumBody(BlockEnumBody node) {
    _checkMembers(node.members);
  }

  void _checkMembers(NodeList<ClassMember> members) {
    final maxNameByScope = <FunctionScope, String>{};
    for (final member in members) {
      if (member is! MethodDeclaration) {
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
