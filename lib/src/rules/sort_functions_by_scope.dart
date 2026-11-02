import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// The scope ordering for functions, getters, and setters within a type body.
enum FunctionScope {
  publicStaticGetter('public static getters'),
  publicStaticSetter('public static setters'),
  publicStatic('public static functions'),
  privateStaticGetter('private static getters'),
  privateStaticSetter('private static setters'),
  privateStatic('private static functions'),
  publicGetter('public getters'),
  publicSetter('public setters'),
  privateGetter('private getters'),
  privateSetter('private setters'),
  publicInstance('public instance functions'),
  privateInstance('private instance functions');

  const FunctionScope(this.description);

  final String description;

  /// Returns the [FunctionScope] for [method], or `null` if [method] is not
  /// subject to scope sorting (such as an operator).
  static FunctionScope? of(MethodDeclaration method) {
    if (method.isOperator) {
      return null;
    }
    final isPrivate = Identifier.isPrivateName(method.name.lexeme);
    if (method.isStatic) {
      if (method.isGetter) {
        return isPrivate
            ? FunctionScope.privateStaticGetter
            : FunctionScope.publicStaticGetter;
      }
      if (method.isSetter) {
        return isPrivate
            ? FunctionScope.privateStaticSetter
            : FunctionScope.publicStaticSetter;
      }
      return isPrivate
          ? FunctionScope.privateStatic
          : FunctionScope.publicStatic;
    }
    if (method.isGetter) {
      return isPrivate
          ? FunctionScope.privateGetter
          : FunctionScope.publicGetter;
    }
    if (method.isSetter) {
      return isPrivate
          ? FunctionScope.privateSetter
          : FunctionScope.publicSetter;
    }
    return isPrivate
        ? FunctionScope.privateInstance
        : FunctionScope.publicInstance;
  }
}

/// A lint rule that enforces sorting functions, getters, and setters by scope:
/// 1. Public static getters
/// 2. Public static setters
/// 3. Public static functions
/// 4. Private static getters
/// 5. Private static setters
/// 6. Private static functions
/// 7. Public getters
/// 8. Public setters
/// 9. Private getters
/// 10. Private setters
/// 11. Public instance functions
/// 12. Private instance functions
class SortFunctionsByScope extends AnalysisRule {
  SortFunctionsByScope()
      : super(
          name: code.lowerCaseName,
          description:
              'Sort functions, getters, and setters by static/instance and visibility scope.',
        );

  static const code = LintCode(
    'sort_functions_by_scope',
    'Sort {0} before {1}.',
    correctionMessage: 'Try sorting functions by scope.',
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

  final SortFunctionsByScope rule;

  @override
  void visitBlockClassBody(BlockClassBody node) {
    _checkMembers(node.members);
  }

  @override
  void visitBlockEnumBody(BlockEnumBody node) {
    _checkMembers(node.members);
  }

  void _checkMembers(NodeList<ClassMember> members) {
    FunctionScope? maxScope;
    for (final member in members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      final scope = FunctionScope.of(member);
      if (scope == null) {
        continue;
      }
      if (maxScope == null || scope.index >= maxScope.index) {
        maxScope = scope;
      } else {
        rule.reportAtToken(
          member.name,
          arguments: [scope.description, maxScope.description],
        );
      }
    }
  }
}
