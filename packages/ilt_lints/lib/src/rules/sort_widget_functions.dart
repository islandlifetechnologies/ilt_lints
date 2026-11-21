import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import '../rule_enabled.dart';

/// Ordering categories for functions, getters, and setters within a Widget
/// class body when [SortWidgetFunctions] is enabled.
enum WidgetFunctionCategory {
  initState("'initState'"),
  didChangeDependencies("'didChangeDependencies'"),
  didUpdateWidget("'didUpdateWidget'"),
  deactivate("'deactivate'"),
  dispose("'dispose'"),
  other('functions'),
  publicBuildPrefix("public 'build*' functions"),
  privateBuildPrefix("private '_build*' functions"),
  build("'build'");

  const WidgetFunctionCategory(this.description);

  final String description;

  /// Returns the [WidgetFunctionCategory] for [method], or `null` if [method]
  /// is not subject to function sorting (such as an operator).
  static WidgetFunctionCategory? of(MethodDeclaration method) {
    if (method.isOperator) {
      return null;
    }
    if (!method.isStatic && !method.isGetter && !method.isSetter) {
      final name = method.name.lexeme;
      switch (name) {
        case 'initState':
          return WidgetFunctionCategory.initState;
        case 'didChangeDependencies':
          return WidgetFunctionCategory.didChangeDependencies;
        case 'didUpdateWidget':
          return WidgetFunctionCategory.didUpdateWidget;
        case 'deactivate':
          return WidgetFunctionCategory.deactivate;
        case 'dispose':
          return WidgetFunctionCategory.dispose;
        case 'build':
          return WidgetFunctionCategory.build;
      }
      if (name.startsWith('build')) {
        return WidgetFunctionCategory.publicBuildPrefix;
      }
      if (name.startsWith('_build')) {
        return WidgetFunctionCategory.privateBuildPrefix;
      }
    }
    return WidgetFunctionCategory.other;
  }

  /// Whether this category is owned by [SortWidgetFunctions] (and therefore
  /// deferred by `sort_functions_by_scope` and
  /// `sort_functions_alphabetically`).
  bool get isOwnedByWidgetRule => this != WidgetFunctionCategory.other;
}

/// A lint rule that enforces widget lifecycle and build method ordering inside
/// Widget classes:
/// 1. `initState`
/// 2. `didChangeDependencies`
/// 3. `didUpdateWidget`
/// 4. `deactivate`
/// 5. `dispose`
/// 6. Other functions, getters, and setters
/// 7. Public `build*` helper functions
/// 8. Private `_build*` helper functions
/// 9. `build`
class SortWidgetFunctions() extends AnalysisRule {
  this
    : super(
        description:
            'Sort widget lifecycle and build functions in a standard order.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'sort_widget_functions',
    'Sort {0} before {1}.',
    correctionMessage: 'Try sorting widget functions in lifecycle order.',
  );

  static const _commonStateSuperclassNames = {
    'AnimatedWidgetBaseState',
    'ConsumerState',
    'HookConsumerState',
    'RestorationMixin',
    'SingleTickerProviderStateMixin',
    'State',
    'TickerProviderStateMixin',
  };

  static const _commonWidgetSuperclassNames = {
    'AnimatedWidget',
    'ConsumerStatefulWidget',
    'ConsumerWidget',
    'HookConsumerWidget',
    'HookWidget',
    'InheritedModel',
    'InheritedNotifier',
    'InheritedTheme',
    'InheritedWidget',
    'LeafRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'ParentDataWidget',
    'PreferredSizeWidget',
    'ProxyWidget',
    'RenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'StatefulWidget',
    'StatelessWidget',
    'Widget',
  };

  /// Returns `true` if `sort_widget_functions` is enabled in
  /// `analysis_options.yaml` starting from [startFile] or [optionsFile].
  ///
  /// Returns `true` when:
  /// - No `analysis_options.yaml` exists (default rule set),
  /// - `sort_widget_functions` is explicitly enabled in `analysis_options.yaml`, or
  /// - `package:ilt_lints/lints.yaml` is included (and `sort_widget_functions`
  ///   is not explicitly disabled).
  ///
  /// Returns `false` when `sort_widget_functions` is explicitly disabled or
  /// when `analysis_options.yaml` configures `ilt_lints` / `linter` rules
  /// without including `package:ilt_lints/lints.yaml` or enabling
  /// `sort_widget_functions`.
  static bool isRuleEnabled(File? startFile, {File? optionsFile}) {
    return isIltRuleEnabled(
      'sort_widget_functions',
      startFile,
      optionsFile: optionsFile,
    );
  }

  /// Returns `true` if [node] is a class declaration that extends or implements
  /// `Widget` (such as `StatelessWidget` or `StatefulWidget`) or `State` (such
  /// as `State<MyWidget>`).
  static bool isWidgetClass(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null &&
        _isElementWidgetOrState(element, <InterfaceElement>{})) {
      return true;
    }

    final extendsClause = node.extendsClause;
    if (extendsClause != null &&
        _isNamedTypeWidgetOrState(extendsClause.superclass)) {
      return true;
    }

    final implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (final type in implementsClause.interfaces) {
        if (_isNamedTypeWidgetOrState(type)) {
          return true;
        }
      }
    }

    final withClause = node.withClause;
    if (withClause != null) {
      for (final type in withClause.mixinTypes) {
        if (_isNamedTypeWidgetOrState(type)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Returns `true` if [body] belongs to a Widget or State [ClassDeclaration].
  static bool isWidgetClassBody(AstNode body) {
    final parent = body.parent;
    return parent is ClassDeclaration && isWidgetClass(parent);
  }

  /// Returns `true` if [element] is, or is a subtype of, `Widget`.
  static bool isWidgetElement(InterfaceElement element) =>
      _isElementWidget(element, <InterfaceElement>{});

  /// Returns `true` if [method] is owned by [SortWidgetFunctions] (lifecycle
  /// methods, `build`, or instance methods prefixed with `build` / `_build`).
  static bool isWidgetOwnedMethod(MethodDeclaration method) {
    final category = WidgetFunctionCategory.of(method);
    return category != null && category.isOwnedByWidgetRule;
  }

  static bool _isElementWidget(
    InterfaceElement element,
    Set<InterfaceElement> visited,
  ) {
    if (!visited.add(element)) {
      return false;
    }
    if (element.name == 'Widget') {
      return true;
    }
    for (final supertype in element.allSupertypes) {
      if (supertype.element.name == 'Widget') {
        return true;
      }
    }
    return false;
  }

  static bool _isElementWidgetOrState(
    InterfaceElement element,
    Set<InterfaceElement> visited,
  ) {
    if (!visited.add(element)) {
      return false;
    }
    if (element.name == 'Widget') {
      return true;
    }
    if (_isStateInterfaceElement(element)) {
      return true;
    }
    for (final supertype in element.allSupertypes) {
      final superElement = supertype.element;
      if (superElement.name == 'Widget' ||
          _isStateInterfaceElement(superElement)) {
        return true;
      }
    }
    return false;
  }

  static bool _isNamedTypeWidget(NamedType namedType) {
    final name = namedType.name.lexeme;
    if (_commonWidgetSuperclassNames.contains(name)) {
      return true;
    }
    final element = namedType.element;
    if (element is InterfaceElement) {
      return _isElementWidget(element, <InterfaceElement>{});
    }
    return false;
  }

  static bool _isNamedTypeWidgetOrState(NamedType namedType) {
    if (_isNamedTypeWidget(namedType)) {
      return true;
    }
    final name = namedType.name.lexeme;
    if (_commonStateSuperclassNames.contains(name)) {
      final typeArgs = namedType.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.isNotEmpty) {
        final firstArg = typeArgs.first;
        if (firstArg is NamedType) {
          final argElement = firstArg.element;
          if (argElement is InterfaceElement) {
            return _isElementWidget(argElement, <InterfaceElement>{});
          }
        }
      }
      return true;
    }
    final element = namedType.element;
    if (element is InterfaceElement) {
      return _isElementWidgetOrState(element, <InterfaceElement>{});
    }
    return false;
  }

  static bool _isStateInterfaceElement(InterfaceElement element) {
    if (!_commonStateSuperclassNames.contains(element.name)) {
      return false;
    }
    for (final typeParam in element.typeParameters) {
      final bound = typeParam.bound;
      if (bound != null) {
        final boundElement = bound.element;
        if (boundElement is InterfaceElement &&
            !_isElementWidget(boundElement, <InterfaceElement>{})) {
          return false;
        }
      }
    }
    return true;
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

class const _Visitor(final SortWidgetFunctions rule)
    extends SimpleAstVisitor<void> {
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!SortWidgetFunctions.isWidgetClass(node)) {
      return;
    }
    final body = node.body;
    if (body is! BlockClassBody) {
      return;
    }
    _checkMembers(body.members);
  }

  void _checkMembers(NodeList<ClassMember> members) {
    final entries = <(MethodDeclaration, WidgetFunctionCategory)>[];
    for (final member in members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      final category = WidgetFunctionCategory.of(member);
      if (category == null) {
        continue;
      }
      entries.add((member, category));
    }

    if (entries.length < 2) {
      return;
    }

    final reported = <MethodDeclaration>{};
    var maxEntry = entries.first;
    for (var i = 1; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.$2.index >= maxEntry.$2.index) {
        maxEntry = entry;
      } else {
        reported.add(entry.$1);
        rule.reportAtToken(
          entry.$1.name,
          arguments: [entry.$2.description, maxEntry.$2.description],
        );
      }
    }

    var minEntry = entries.last;
    for (var i = entries.length - 2; i >= 0; i--) {
      final entry = entries[i];
      if (entry.$2.index <= minEntry.$2.index) {
        minEntry = entry;
      } else if (entry.$2.isOwnedByWidgetRule && !reported.contains(entry.$1)) {
        rule.reportAtToken(
          entry.$1.name,
          arguments: [minEntry.$2.description, entry.$2.description],
        );
      }
    }
  }
}
