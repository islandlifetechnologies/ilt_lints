import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// The scope ordering for fields within a type body.
enum FieldScope {
  publicStaticConst('public static const fields'),
  privateStaticConst('private static const fields'),
  publicStatic('public static fields'),
  privateStatic('private static fields'),
  publicInstance('public instance fields'),
  privateInstance('private instance fields');

  const FieldScope(this.description);

  final String description;

  /// Returns the [FieldScope] for [field].
  static FieldScope of(FieldDeclaration field) {
    final name = field.fields.variables.first.name.lexeme;
    final isPrivate = Identifier.isPrivateName(name);
    if (field.isStatic) {
      if (field.fields.isConst) {
        return isPrivate
            ? FieldScope.privateStaticConst
            : FieldScope.publicStaticConst;
      }
      return isPrivate ? FieldScope.privateStatic : FieldScope.publicStatic;
    }
    return isPrivate ? FieldScope.privateInstance : FieldScope.publicInstance;
  }
}

/// A lint rule that enforces sorting class-level fields above all methods,
/// getters, setters, and operators (ignoring constructors), grouped by
/// [FieldScope] and sorted alphabetically within each scope:
/// 1. Public `static const` fields
/// 2. Private `static const` fields
/// 3. Public `static` fields
/// 4. Private `static` fields
/// 5. Public instance fields
/// 6. Private instance fields
class SortFields extends AnalysisRule {
  SortFields()
      : super(
          name: code.lowerCaseName,
          description:
              'Sort fields above methods by scope and alphabetically within each scope.',
        );

  static const code = LintCode(
    'sort_fields',
    'Sort {0}.',
    correctionMessage:
        'Try sorting fields by scope and alphabetically above methods.',
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

  final SortFields rule;

  @override
  void visitBlockClassBody(BlockClassBody node) {
    _checkMembers(node.members);
  }

  @override
  void visitBlockEnumBody(BlockEnumBody node) {
    _checkMembers(node.members);
  }

  void _checkMembers(NodeList<ClassMember> members) {
    var seenMethod = false;
    FieldScope? maxScope;
    final maxNameByScope = <FieldScope, String>{};

    for (final member in members) {
      if (member is MethodDeclaration) {
        seenMethod = true;
        continue;
      }
      if (member is! FieldDeclaration) {
        continue;
      }

      final firstVariable = member.fields.variables.first;
      final name = firstVariable.name.lexeme;
      final scope = FieldScope.of(member);

      String? problem;
      if (seenMethod) {
        problem = '${scope.description} before methods';
      } else if (maxScope != null && scope.index < maxScope.index) {
        problem = '${scope.description} before ${maxScope.description}';
      } else {
        final maxName = maxNameByScope[scope];
        if (maxName != null && name.compareTo(maxName) < 0) {
          problem = "${scope.description} alphabetically ('$name' before '$maxName')";
        }
      }

      if (problem != null) {
        rule.reportAtToken(
          firstVariable.name,
          arguments: [problem],
        );
      }

      if (maxScope == null || scope.index >= maxScope.index) {
        maxScope = scope;
      }
      final currentMaxName = maxNameByScope[scope];
      if (currentMaxName == null || name.compareTo(currentMaxName) >= 0) {
        maxNameByScope[scope] = name;
      }
    }
  }
}

