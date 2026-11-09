import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Result of analyzing a [ClassDeclaration] for [PreferPrimaryConstructors].
class PreferPrimaryConstructorsAnalysis {
  const PreferPrimaryConstructorsAnalysis({
    required this.classNameToken,
    required this.classNode,
    required this.hasSingleGenerativeConstructor,
    required this.targetConstructor,
  });

  final Token classNameToken;
  final ClassDeclaration classNode;
  final bool hasSingleGenerativeConstructor;
  final ConstructorDeclaration? targetConstructor;
}

/// A lint rule that flags classes that do not use a primary constructor.
class PreferPrimaryConstructors extends AnalysisRule {
  PreferPrimaryConstructors()
    : super(
        description: 'Prefer using a primary constructor for classes.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'prefer_primary_constructors',
    "Prefer using a primary constructor for class '{0}'.",
    correctionMessage: 'Try converting the class to use a primary constructor.',
  );

  /// Analyzes [node] and returns a [PreferPrimaryConstructorsAnalysis] if
  /// [node] should be converted to use a primary constructor, or `null` if it
  /// already uses one or cannot use one.
  static PreferPrimaryConstructorsAnalysis? analyzeClass(
    ClassDeclaration node,
  ) {
    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    if (unit != null && unit.directives.any((d) => d is PartOfDirective)) {
      return null;
    }
    if (node.namePart is PrimaryConstructorDeclaration) {
      return null;
    }
    if (node.mixinKeyword != null) {
      return null;
    }
    final body = node.body;
    if (body is! BlockClassBody) {
      return null;
    }

    final generativeConstructors = <ConstructorDeclaration>[];
    final redirectingGenerativeConstructors = <ConstructorDeclaration>[];
    var hasUnnamedFactory = false;

    for (final member in body.members) {
      if (member is! ConstructorDeclaration) {
        continue;
      }
      if (member.factoryKeyword != null) {
        if (member.name == null) {
          hasUnnamedFactory = true;
        }
        continue;
      }
      if (member.redirectedConstructor != null) {
        redirectingGenerativeConstructors.add(member);
      } else {
        generativeConstructors.add(member);
      }
    }

    if (generativeConstructors.isEmpty) {
      if (redirectingGenerativeConstructors.isNotEmpty || hasUnnamedFactory) {
        return null;
      }
      return PreferPrimaryConstructorsAnalysis(
        classNameToken: node.namePart.typeName,
        classNode: node,
        hasSingleGenerativeConstructor: false,
        targetConstructor: null,
      );
    }

    ConstructorDeclaration? targetConstructor;
    for (final ctor in generativeConstructors) {
      if (ctor.name == null) {
        targetConstructor = ctor;
        break;
      }
    }
    targetConstructor ??= generativeConstructors.first;

    if (targetConstructor.externalKeyword != null) {
      return null;
    }

    return PreferPrimaryConstructorsAnalysis(
      classNameToken: node.namePart.typeName,
      classNode: node,
      hasSingleGenerativeConstructor: generativeConstructors.length == 1,
      targetConstructor: targetConstructor,
    );
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

  final PreferPrimaryConstructors rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final analysis = PreferPrimaryConstructors.analyzeClass(node);
    if (analysis == null) {
      return;
    }
    rule.reportAtToken(
      analysis.classNameToken,
      arguments: [analysis.classNameToken.lexeme],
    );
  }
}
