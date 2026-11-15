import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

/// A lint rule that flags usages of `DateTime.now()` and `DateTime.now` in
/// files under `lib/` and recommends using `clock.now()` / `clock.now` from
/// `package:clock/clock.dart` so that time can be mocked in tests.
class UseClock extends AnalysisRule {
  UseClock()
    : super(
        description: 'Use clock.now() instead of DateTime.now() so that time can be mocked in tests.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'use_clock',
    "Use 'clock.now' instead of 'DateTime.now' so time can be mocked in tests.",
    correctionMessage: "Try replacing 'DateTime.now' with 'clock.now'.",
  );

  /// Finds the enclosing [AstNode] representing a `DateTime.now()` call or
  /// `DateTime.now` tear-off starting from [node], or `null` if none matches.
  static AstNode? findTargetNode(AstNode? node) {
    var current = node;
    while (current != null) {
      if (isDateTimeNowCall(current) || isDateTimeNowTearOff(current)) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  /// Returns `true` if [node] is a `DateTime.now()` invocation.
  static bool isDateTimeNowCall(AstNode node) {
    if (_isInsideComment(node)) {
      return false;
    }
    if (node is InstanceCreationExpression) {
      final constructorName = node.constructorName;
      if (constructorName.name?.name != 'now' ||
          node.argumentList.arguments.isNotEmpty) {
        return false;
      }
      if (constructorName.type.name.lexeme != 'DateTime') {
        return false;
      }
      final element =
          constructorName.element?.enclosingElement ??
          constructorName.type.element;
      return _isDartCoreDateTime(element);
    }
    if (node is MethodInvocation) {
      if (node.methodName.name != 'now' ||
          node.argumentList.arguments.isNotEmpty) {
        return false;
      }
      final target = node.target;
      if (target == null || !_isDateTimeTarget(target)) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// Returns `true` if [node] is a `DateTime.now` constructor tear-off.
  static bool isDateTimeNowTearOff(AstNode node) {
    if (_isInsideComment(node)) {
      return false;
    }
    if (node is ConstructorReference) {
      final constructorName = node.constructorName;
      if (constructorName.name?.name != 'now') {
        return false;
      }
      if (constructorName.type.name.lexeme != 'DateTime') {
        return false;
      }
      final element =
          constructorName.element?.enclosingElement ??
          constructorName.type.element;
      return _isDartCoreDateTime(element);
    }
    if (node is PrefixedIdentifier) {
      final parent = node.parent;
      if (parent is ConstructorName ||
          parent is NamedType ||
          parent is MethodInvocation ||
          parent is PropertyAccess ||
          parent is InstanceCreationExpression ||
          parent is ConstructorReference) {
        return false;
      }
      if (node.prefix.name != 'DateTime' || node.identifier.name != 'now') {
        return false;
      }
      return _isDartCoreDateTime(node.prefix.element);
    }
    if (node is PropertyAccess) {
      final parent = node.parent;
      if (parent is MethodInvocation ||
          parent is PropertyAccess ||
          parent is InstanceCreationExpression ||
          parent is ConstructorReference) {
        return false;
      }
      if (node.propertyName.name != 'now') {
        return false;
      }
      final target = node.target;
      if (target == null || !_isDateTimeTarget(target)) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// Returns `true` if [file] is inside a package's `lib` directory (and not
  /// inside a `test` directory).
  static bool isFileInLibFolder(File file) {
    final pathContext = file.provider.pathContext;
    final pubspecFile = _findFileUpwards(file, 'pubspec.yaml');
    if (pubspecFile != null && pubspecFile.exists) {
      final packageRoot = pubspecFile.parent;
      final libFolder = packageRoot.getFolder('lib');
      return pathContext.isWithin(libFolder.path, file.path);
    }

    var folder = file.parent;
    while (true) {
      final name = folder.shortName;
      if (name == 'test') {
        return false;
      }
      if (name == 'lib') {
        return true;
      }
      final parent = folder.parent;
      if (parent.path == folder.path) {
        break;
      }
      folder = parent;
    }
    return false;
  }

  static File? _findFileUpwards(File startFile, String fileName) {
    var folder = startFile.parent;
    while (true) {
      final candidate = folder.getFile(fileName);
      if (candidate.exists) {
        return candidate;
      }
      final parent = folder.parent;
      if (parent.path == folder.path) {
        break;
      }
      folder = parent;
    }
    return null;
  }

  static bool _isDartCoreDateTime(Element? element) {
    if (element == null) {
      return true;
    }
    if (element is! InterfaceElement && element is! TypeAliasElement) {
      return false;
    }
    if (element.name != 'DateTime') {
      return false;
    }
    final library = element.library;
    return library == null || library.isDartCore;
  }

  static bool _isDateTimeTarget(Expression target) {
    if (target is SimpleIdentifier) {
      if (target.name != 'DateTime') {
        return false;
      }
      return _isDartCoreDateTime(target.element);
    }
    if (target is PrefixedIdentifier) {
      if (target.identifier.name != 'DateTime') {
        return false;
      }
      return _isDartCoreDateTime(target.identifier.element);
    }
    return false;
  }

  static bool _isInsideComment(AstNode node) =>
      node.thisOrAncestorOfType<Comment>() != null ||
      node.thisOrAncestorOfType<CommentReference>() != null;

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final file = context.currentUnit?.file ?? context.definingUnit.file;
    if (!isFileInLibFolder(file)) {
      return;
    }
    final visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addMethodInvocation(this, visitor);
    registry.addConstructorReference(this, visitor);
    registry.addPrefixedIdentifier(this, visitor);
    registry.addPropertyAccess(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final UseClock rule;

  @override
  void visitConstructorReference(ConstructorReference node) {
    if (UseClock.isDateTimeNowTearOff(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (UseClock.isDateTimeNowCall(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (UseClock.isDateTimeNowCall(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (UseClock.isDateTimeNowTearOff(node)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (UseClock.isDateTimeNowTearOff(node)) {
      rule.reportAtNode(node);
    }
  }
}
