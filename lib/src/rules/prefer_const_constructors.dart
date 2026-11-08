import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

/// Result of analyzing a [ClassDeclaration] for [PreferConstConstructors].
class PreferConstConstructorsAnalysis {
  const PreferConstConstructorsAnalysis({
    required this.classNode,
    required this.isPrimaryConstructor,
    required this.reportToken,
    required this.targetConstructors,
  });

  final ClassDeclaration classNode;
  final bool isPrimaryConstructor;
  final Token reportToken;
  final List<ConstructorDeclaration> targetConstructors;
}

/// A lint rule that determines whether a class's constructor (primary or
/// generative) can be marked `const` without any other changes and flags it if
/// it is not already `const`.
class PreferConstConstructors extends AnalysisRule {
  PreferConstConstructors()
    : super(
        description: 'Prefer marking constructors const when the class can be const without other changes.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'prefer_const_constructors',
    "Prefer marking constructor of '{0}' as 'const'.",
    correctionMessage: "Try adding the 'const' modifier to the constructor.",
  );

  /// Analyzes [node] and returns a [PreferConstConstructorsAnalysis] if [node]
  /// has a primary constructor or generative constructor(s) that can be marked
  /// `const` without any other changes, or `null` otherwise.
  static PreferConstConstructorsAnalysis? analyzeClass(ClassDeclaration node) {
    if (node.mixinKeyword != null) {
      return null;
    }
    final body = node.body;
    if (body is! BlockClassBody) {
      return null;
    }

    if (_hasMutableMixinFields(node)) {
      return null;
    }

    // All instance fields declared in the class body must be `final` (not
    // `late`) and any field initializers must be constant expressions.
    for (final member in body.members) {
      if (member is! FieldDeclaration || member.isStatic) {
        continue;
      }
      if (!member.fields.isFinal || member.fields.isLate) {
        return null;
      }
      for (final variable in member.fields.variables) {
        final initializer = variable.initializer;
        if (initializer != null &&
            !_isPotentiallyConstant(
              initializer,
              allowedParamNames: const {},
              inConstContext: member.fields.isConst,
            )) {
          return null;
        }
      }
    }

    // Check resolved class element fields as well (including declaring parameters).
    final classElement = node.declaredFragment?.element;
    if (classElement != null) {
      for (final field in classElement.fields) {
        if (field.isStatic || !field.isOriginDeclaration) {
          continue;
        }
        if (!field.isFinal || field.isLate) {
          return null;
        }
      }
    }

    final namePart = node.namePart;
    if (namePart is PrimaryConstructorDeclaration) {
      if (namePart.constKeyword != null) {
        return null;
      }
      if (!_canPrimaryConstructorBeConst(node, namePart, body)) {
        return null;
      }
      return PreferConstConstructorsAnalysis(
        classNode: node,
        isPrimaryConstructor: true,
        reportToken: namePart.typeName,
        targetConstructors: const [],
      );
    }

    final candidateConstructors = <ConstructorDeclaration>[];
    for (final member in body.members) {
      if (member is! ConstructorDeclaration) {
        continue;
      }
      if (member.factoryKeyword != null || member.constKeyword != null) {
        continue;
      }
      if (_canConstructorBeConst(
        node,
        member,
        visiting: <ConstructorDeclaration>{},
      )) {
        candidateConstructors.add(member);
      }
    }

    if (candidateConstructors.isEmpty) {
      return null;
    }

    return PreferConstConstructorsAnalysis(
      classNode: node,
      isPrimaryConstructor: false,
      reportToken: namePart.typeName,
      targetConstructors: candidateConstructors,
    );
  }

  static bool _canConstructorBeConst(
    ClassDeclaration classNode,
    ConstructorDeclaration ctor, {
    required Set<ConstructorDeclaration> visiting,
  }) {
    if (!visiting.add(ctor)) {
      return false;
    }
    if (ctor.externalKeyword != null || ctor.body is! EmptyFunctionBody) {
      return false;
    }
    if (!_isParameterListConst(ctor.parameters, checkDeclaringVar: false)) {
      return false;
    }
    final paramNames = {
      for (final param in ctor.parameters.parameters)
        if (param.name != null) param.name!.lexeme,
    };
    return _isInitializerListConst(
      classNode,
      ctor.initializers,
      paramNames: paramNames,
      redirectedConstructor: ctor.redirectedConstructor,
      visiting: visiting,
    );
  }

  static bool _canPrimaryConstructorBeConst(
    ClassDeclaration classNode,
    PrimaryConstructorDeclaration primary,
    BlockClassBody body,
  ) {
    if (!_isParameterListConst(
      primary.formalParameters,
      checkDeclaringVar: true,
    )) {
      return false;
    }

    final paramNames = {
      for (final param in primary.formalParameters.parameters)
        if (param.name != null) param.name!.lexeme,
    };

    final primaryBodies = body.members
        .whereType<PrimaryConstructorBody>()
        .toList();
    if (primaryBodies.isEmpty) {
      return _hasConstDefaultSuperConstructor(classNode);
    }

    for (final primaryBody in primaryBodies) {
      if (primaryBody.body is! EmptyFunctionBody) {
        return false;
      }
      if (!_isInitializerListConst(
        classNode,
        primaryBody.initializers,
        paramNames: paramNames,
        redirectedConstructor: null,
        visiting: <ConstructorDeclaration>{},
      )) {
        return false;
      }
    }
    return true;
  }

  static bool _canTargetConstructorInSameClassBeConst(
    ClassDeclaration classNode,
    ConstructorElement? targetElement,
    Set<ConstructorDeclaration> visiting,
  ) {
    if (targetElement == null) {
      return false;
    }
    if (targetElement.isConst) {
      return true;
    }
    final classElement = classNode.declaredFragment?.element;
    if (classElement == null ||
        targetElement.enclosingElement != classElement) {
      return false;
    }
    final body = classNode.body;
    if (body is! BlockClassBody) {
      return false;
    }
    for (final member in body.members) {
      if (member is ConstructorDeclaration &&
          member.declaredFragment?.element == targetElement) {
        return _canConstructorBeConst(
          classNode,
          member,
          visiting: {...visiting},
        );
      }
    }
    return false;
  }

  static bool _hasConstDefaultSuperConstructor(ClassDeclaration classNode) {
    final extendsClause = classNode.extendsClause;
    if (extendsClause == null) {
      return true;
    }
    final superName = extendsClause.superclass.name.lexeme;
    if (superName == 'Object') {
      return true;
    }
    final superElement = extendsClause.superclass.element;
    if (superElement is! InterfaceElement) {
      return false;
    }
    final unnamedCtor = superElement.unnamedConstructor;
    return unnamedCtor != null && unnamedCtor.isConst;
  }

  static bool _hasMutableMixinFields(ClassDeclaration classNode) {
    final withClause = classNode.withClause;
    if (withClause == null) {
      return false;
    }
    for (final mixinType in withClause.mixinTypes) {
      final element = mixinType.element;
      if (element is! InterfaceElement) {
        return true;
      }
      if (element.fields.any((f) => !f.isStatic && f.isOriginDeclaration)) {
        return true;
      }
    }
    return false;
  }

  static bool _isConstElement(Element? element) {
    if (element == null) {
      return false;
    }
    if (element is VariableElement) {
      return element.isConst;
    }
    if (element is PropertyAccessorElement) {
      return element.variable.isConst;
    }
    if (element is ExecutableElement) {
      return element.isStatic || element is TopLevelFunctionElement;
    }
    if (element is InterfaceElement ||
        element is TypeAliasElement ||
        element is PrefixElement) {
      return true;
    }
    return false;
  }

  static bool _isInitializerListConst(
    ClassDeclaration classNode,
    NodeList<ConstructorInitializer> initializers, {
    required Set<String> paramNames,
    required ConstructorName? redirectedConstructor,
    required Set<ConstructorDeclaration> visiting,
  }) {
    if (redirectedConstructor != null) {
      final targetElement = redirectedConstructor.element;
      if (!_canTargetConstructorInSameClassBeConst(
        classNode,
        targetElement,
        visiting,
      )) {
        return false;
      }
    }

    var hasExplicitSuperOrRedirect = redirectedConstructor != null;
    for (final initializer in initializers) {
      if (initializer is ConstructorFieldInitializer) {
        if (!_isPotentiallyConstant(
          initializer.expression,
          allowedParamNames: paramNames,
          inConstContext: false,
        )) {
          return false;
        }
      } else if (initializer is AssertInitializer) {
        if (!_isPotentiallyConstant(
          initializer.condition,
          allowedParamNames: paramNames,
          inConstContext: false,
        )) {
          return false;
        }
        final message = initializer.message;
        if (message != null &&
            !_isPotentiallyConstant(
              message,
              allowedParamNames: paramNames,
              inConstContext: false,
            )) {
          return false;
        }
      } else if (initializer is SuperConstructorInvocation) {
        hasExplicitSuperOrRedirect = true;
        final superElement = initializer.element;
        if (superElement == null || !superElement.isConst) {
          return false;
        }
        for (final arg in initializer.argumentList.arguments) {
          if (!_isPotentiallyConstant(
            arg.argumentExpression,
            allowedParamNames: paramNames,
            inConstContext: false,
          )) {
            return false;
          }
        }
      } else if (initializer is RedirectingConstructorInvocation) {
        hasExplicitSuperOrRedirect = true;
        final targetElement = initializer.element;
        if (!_canTargetConstructorInSameClassBeConst(
          classNode,
          targetElement,
          visiting,
        )) {
          return false;
        }
        for (final arg in initializer.argumentList.arguments) {
          if (!_isPotentiallyConstant(
            arg.argumentExpression,
            allowedParamNames: paramNames,
            inConstContext: false,
          )) {
            return false;
          }
        }
      } else {
        return false;
      }
    }

    if (!hasExplicitSuperOrRedirect &&
        !_hasConstDefaultSuperConstructor(classNode)) {
      return false;
    }
    return true;
  }

  static bool _isParameterListConst(
    FormalParameterList parameterList, {
    required bool checkDeclaringVar,
  }) {
    for (final param in parameterList.parameters) {
      if (checkDeclaringVar && param.varKeyword != null) {
        return false;
      }
      final defaultValue = param.defaultClause?.value;
      if (defaultValue != null &&
          !_isPotentiallyConstant(
            defaultValue,
            allowedParamNames: const {},
            inConstContext: true,
          )) {
        return false;
      }
    }
    return true;
  }

  static bool _isPotentiallyConstant(
    Expression expr, {
    required Set<String> allowedParamNames,
    required bool inConstContext,
  }) {
    if (expr is BooleanLiteral ||
        expr is DoubleLiteral ||
        expr is IntegerLiteral ||
        expr is NullLiteral ||
        expr is SimpleStringLiteral ||
        expr is SymbolLiteral) {
      return true;
    }

    if (expr is AdjacentStrings) {
      return expr.strings.every(
        (s) => _isPotentiallyConstant(
          s,
          allowedParamNames: allowedParamNames,
          inConstContext: inConstContext,
        ),
      );
    }

    if (expr is StringInterpolation) {
      for (final element in expr.elements) {
        if (element is InterpolationExpression &&
            !_isPotentiallyConstant(
              element.expression,
              allowedParamNames: allowedParamNames,
              inConstContext: inConstContext,
            )) {
          return false;
        }
      }
      return true;
    }

    if (expr is ParenthesizedExpression) {
      return _isPotentiallyConstant(
        expr.expression,
        allowedParamNames: allowedParamNames,
        inConstContext: inConstContext,
      );
    }

    if (expr is SimpleIdentifier) {
      if (allowedParamNames.contains(expr.name)) {
        return true;
      }
      return _isConstElement(expr.element);
    }

    if (expr is PrefixedIdentifier) {
      if (allowedParamNames.contains(expr.prefix.name) &&
          expr.identifier.name == 'length') {
        return true;
      }
      return _isConstElement(expr.identifier.element);
    }

    if (expr is PropertyAccess) {
      return _isConstElement(expr.propertyName.element);
    }

    if (expr is PrefixExpression) {
      final op = expr.operator.type;
      if (op != TokenType.BANG &&
          op != TokenType.MINUS &&
          op != TokenType.TILDE) {
        return false;
      }
      return _isPotentiallyConstant(
        expr.operand,
        allowedParamNames: allowedParamNames,
        inConstContext: inConstContext,
      );
    }

    if (expr is BinaryExpression) {
      return _isPotentiallyConstant(
            expr.leftOperand,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          ) &&
          _isPotentiallyConstant(
            expr.rightOperand,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          );
    }

    if (expr is ConditionalExpression) {
      return _isPotentiallyConstant(
            expr.condition,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          ) &&
          _isPotentiallyConstant(
            expr.thenExpression,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          ) &&
          _isPotentiallyConstant(
            expr.elseExpression,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          );
    }

    if (expr is ListLiteral) {
      if (expr.constKeyword == null && !inConstContext) {
        return false;
      }
      for (final element in expr.elements) {
        if (element is! Expression ||
            !_isPotentiallyConstant(
              element,
              allowedParamNames: allowedParamNames,
              inConstContext: true,
            )) {
          return false;
        }
      }
      return true;
    }

    if (expr is SetOrMapLiteral) {
      if (expr.constKeyword == null && !inConstContext) {
        return false;
      }
      for (final element in expr.elements) {
        if (element is Expression) {
          if (!_isPotentiallyConstant(
            element,
            allowedParamNames: allowedParamNames,
            inConstContext: true,
          )) {
            return false;
          }
        } else if (element is MapLiteralEntry) {
          if (!_isPotentiallyConstant(
                element.key,
                allowedParamNames: allowedParamNames,
                inConstContext: true,
              ) ||
              !_isPotentiallyConstant(
                element.value,
                allowedParamNames: allowedParamNames,
                inConstContext: true,
              )) {
            return false;
          }
        } else {
          return false;
        }
      }
      return true;
    }

    if (expr is InstanceCreationExpression) {
      if (!expr.isConst && !inConstContext) {
        return false;
      }
      final ctorElement = expr.constructorName.element;
      if (ctorElement != null && !ctorElement.isConst) {
        return false;
      }
      for (final arg in expr.argumentList.arguments) {
        if (!_isPotentiallyConstant(
          arg.argumentExpression,
          allowedParamNames: allowedParamNames,
          inConstContext: true,
        )) {
          return false;
        }
      }
      return true;
    }

    if (expr is MethodInvocation) {
      if (expr.target == null &&
          expr.methodName.name == 'identical' &&
          expr.argumentList.arguments.length == 2) {
        return expr.argumentList.arguments.every(
          (arg) => _isPotentiallyConstant(
            arg.argumentExpression,
            allowedParamNames: allowedParamNames,
            inConstContext: inConstContext,
          ),
        );
      }
      return false;
    }

    if (expr is ConstructorReference) {
      final ctorElement = expr.constructorName.element;
      return ctorElement != null && ctorElement.isConst;
    }

    if (expr is FunctionReference) {
      return _isPotentiallyConstant(
        expr.function,
        allowedParamNames: allowedParamNames,
        inConstContext: inConstContext,
      );
    }

    if (expr is TypeLiteral) {
      return expr.type.element is InterfaceElement ||
          expr.type.element is TypeAliasElement;
    }

    return false;
  }

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addClassDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final PreferConstConstructors rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final analysis = PreferConstConstructors.analyzeClass(node);
    if (analysis == null) {
      return;
    }
    rule.reportAtToken(
      analysis.reportToken,
      arguments: [analysis.reportToken.lexeme],
    );
  }
}
