import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'sort_widget_functions.dart';

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
class SortFunctionsByScope({final bool? deferToSortWidgetFunctions})
    extends AnalysisRule {
  this
    : super(
        description: 'Sort functions, getters, and setters by static/instance and visibility scope.',
        name: code.lowerCaseName,
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
  final SortFunctionsByScope rule, {
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
    FunctionScope? maxScope;
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
