import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import '../rule_enabled.dart';
import 'sort_named_parameters.dart';
import 'sort_widget_functions.dart';

/// A lint rule that requires the `child`, `children`, `builder`, and
/// `itemBuilder` named parameters of a widget to come after all other named
/// parameters, sorted alphabetically among themselves.
///
/// Applies to constructor declarations of `Widget` classes and to named
/// arguments of widget constructor invocations. When this rule triggers, it
/// takes priority over `sort_named_parameters` for these parameters.
class SortWidgetParameters() extends AnalysisRule {
  this
    : super(
        description:
            'Sort widget child/builder parameters after other parameters.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'sort_widget_parameters',
    "Sort widget parameter '{0}' after all other named parameters, in "
        'alphabetical order.',
    correctionMessage:
        'Try moving child, children, builder and itemBuilder parameters to the '
        'end.',
  );

  /// Parameter names that are sorted last in widgets.
  static const trailingNames = {'builder', 'child', 'children', 'itemBuilder'};

  /// Returns `true` if `sort_widget_parameters` is enabled in
  /// `analysis_options.yaml` starting from [startFile] or [optionsFile].
  static bool isRuleEnabled(File? startFile, {File? optionsFile}) =>
      isIltRuleEnabled(code.lowerCaseName, startFile, optionsFile: optionsFile);

  /// Whether [name] (leading underscores ignored) is a trailing widget
  /// parameter name.
  static bool isTrailingName(String name) =>
      trailingNames.contains(SortNamedParameters.normalizeParameterName(name));

  /// Whether [list] is the argument list of a widget constructor invocation.
  static bool isWidgetArgumentList(ArgumentList list) {
    final parent = list.parent;
    if (parent is! InstanceCreationExpression) {
      return false;
    }
    final element = parent.constructorName.type.element;
    return element is InterfaceElement &&
        SortWidgetFunctions.isWidgetElement(element);
  }

  /// Whether [list] declares the parameters of a constructor of a widget.
  static bool isWidgetParameterList(FormalParameterList list) {
    final parent = list.parent;
    if (parent is! ConstructorDeclaration &&
        parent is! PrimaryConstructorDeclaration) {
      return false;
    }
    final classNode = list.thisOrAncestorOfType<ClassDeclaration>();
    return classNode != null && SortWidgetFunctions.isWidgetClass(classNode);
  }

  /// Returns the indexes into [names] that violate this rule: trailing names
  /// followed by a non-trailing name, or trailing names out of alphabetical
  /// order.
  static Set<int> violations(List<String> names) {
    final result = <int>{};
    var lastNonTrailing = -1;
    for (var i = 0; i < names.length; i++) {
      if (!isTrailingName(names[i])) {
        lastNonTrailing = i;
      }
    }
    String? maxTrailing;
    for (var i = 0; i < names.length; i++) {
      if (!isTrailingName(names[i])) {
        continue;
      }
      final name = SortNamedParameters.normalizeParameterName(names[i]);
      if (i < lastNonTrailing) {
        result.add(i);
      }
      if (maxTrailing == null || name.compareTo(maxTrailing) >= 0) {
        maxTrailing = name;
      } else {
        result.add(i);
      }
    }
    return result;
  }

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addArgumentList(this, visitor);
    registry.addFormalParameterList(this, visitor);
  }
}

class const _Visitor(final SortWidgetParameters rule)
    extends SimpleAstVisitor<void> {
  @override
  void visitArgumentList(ArgumentList node) {
    if (!SortWidgetParameters.isWidgetArgumentList(node)) {
      return;
    }
    final arguments = node.arguments.whereType<NamedArgument>().toList();
    final names = [for (final a in arguments) a.name.lexeme];
    for (final index in SortWidgetParameters.violations(names)) {
      rule.reportAtToken(arguments[index].name, arguments: [names[index]]);
    }
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    if (!SortWidgetParameters.isWidgetParameterList(node)) {
      return;
    }
    final parameters = [
      for (final p in node.parameters)
        if (p.isNamed && p.name != null) p,
    ];
    final names = [for (final p in parameters) p.name!.lexeme];
    for (final index in SortWidgetParameters.violations(names)) {
      rule.reportAtToken(parameters[index].name!, arguments: [names[index]]);
    }
  }
}
