import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

/// A lint rule that flags direct usages of `dart:io` file system types and
/// constructors (`File`, `Directory`, `FileSystemEntity`, `Link`) in files
/// under `lib/` and recommends using `FileSystem` from `package:file/file.dart`.
class UseFileSystem extends AnalysisRule {
  UseFileSystem()
    : super(
        description: 'Use FileSystem from package:file instead of dart:io File, Directory, and FileSystemEntity.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'use_file_system',
    "Use 'FileSystem' from 'package:file/file.dart' instead of 'dart:io' '{0}'.",
    correctionMessage:
        "Try using a 'FileSystem' instance from 'package:file/file.dart'.",
  );

  static const targetTypeNames = {
    'Directory',
    'File',
    'FileSystemEntity',
    'Link',
  };

  static const _constructibleTypeNames = {'Directory', 'File', 'Link'};

  static const _directoryStaticProperties = {
    'current': 'currentDirectory',
    'systemTemp': 'systemTempDirectory',
  };

  static const _entityStaticMethods = {
    'identical',
    'identicalSync',
    'isDirectory',
    'isDirectorySync',
    'isFile',
    'isFileSync',
    'isLink',
    'isLinkSync',
    'type',
    'typeSync',
  };

  static const _factoryConstructorNames = {'fromRawPath', 'fromUri'};

  /// Finds the enclosing [AstNode] flagged by [UseFileSystem] starting from
  /// [node], or `null` if none matches.
  static AstNode? findTargetNode(AstNode? node) {
    var current = node;
    while (current != null) {
      if (isFileSystemCallOrAccess(current) || isFileSystemNamedType(current)) {
        return current;
      }
      current = current.parent;
    }
    return null;
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

  /// Returns `true` if [node] is a direct constructor invocation, static
  /// factory call, or static property access on `File`, `Directory`, `Link`, or
  /// `FileSystemEntity` (such as `File(path)`, `Directory(path)`,
  /// `Directory.current`, `Directory.systemTemp`, `File.fromUri(uri)`).
  static bool isFileSystemCallOrAccess(AstNode node) =>
      targetNameForCallOrAccess(node) != null;

  /// Returns `true` if [node] is a [NamedType] referring to `dart:io`'s
  /// `File`, `Directory`, `FileSystemEntity`, or `Link` (and not the type child
  /// of a [ConstructorName] already covered by [isFileSystemCallOrAccess]).
  static bool isFileSystemNamedType(AstNode node) {
    if (node is! NamedType || _isInsideComment(node)) {
      return false;
    }
    if (node.parent is ConstructorName) {
      return false;
    }
    final typeName = node.name.lexeme;
    if (!targetTypeNames.contains(typeName)) {
      return false;
    }
    final element = node.element;
    if (element != null) {
      return _isDartIoElement(element);
    }
    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    if (unit == null) {
      return false;
    }
    return _hasActiveDartIoImportFor(
      unit,
      prefix: node.importPrefix?.name.lexeme,
      symbolName: typeName,
    );
  }

  /// Rewrites a direct `File`, `Directory`, `Link`, or `FileSystemEntity` call
  /// or static property access [node] using [fsAccess] (for example, `_fs`,
  /// or `fs`), or returns `null` if [node] is not a supported call or property
  /// access.
  static String? rewriteCallOrAccess(
    AstNode node, {
    required String fsAccess,
    required String Function(AstNode) getNodeText,
  }) {
    String rewriteArg(AstNode arg) =>
        rewriteCallOrAccess(
          arg,
          fsAccess: fsAccess,
          getNodeText: getNodeText,
        ) ??
        getNodeText(arg);

    if (node is InstanceCreationExpression) {
      final typeName = node.constructorName.type.name.lexeme;
      final method = _methodForConstructibleType(typeName);
      if (method == null) {
        return null;
      }
      final args = node.argumentList.arguments.map(rewriteArg).join(', ');
      return '$fsAccess.$method($args)';
    }

    if (node is MethodInvocation) {
      final target = node.target;
      final methodName = node.methodName.name;
      final args = node.argumentList.arguments.map(rewriteArg).join(', ');

      if (target == null) {
        final method = _methodForConstructibleType(methodName);
        if (method == null) {
          return null;
        }
        return '$fsAccess.$method($args)';
      }

      final targetType = _extractTargetTypeName(target);
      if (targetType == null) {
        return null;
      }

      if (_constructibleTypeNames.contains(targetType) &&
          _parenthesizedConstructorOrFactory(target, methodName)) {
        final method = _methodForConstructibleType(
          _modType(target, methodName),
        );
        if (method != null) {
          return '$fsAccess.$method($args)';
        }
      }

      if (targetType == 'FileSystemEntity' &&
          _entityStaticMethods.contains(methodName)) {
        return '$fsAccess.$methodName($args)';
      }
    }

    if (node is PrefixedIdentifier) {
      if (node.prefix.name == 'Directory') {
        final replacementProp =
            _directoryStaticProperties[node.identifier.name];
        if (replacementProp != null) {
          return '$fsAccess.$replacementProp';
        }
      }
    }

    if (node is PropertyAccess) {
      final targetType = node.target != null
          ? _extractTargetTypeName(node.target!)
          : null;
      if (targetType == 'Directory') {
        final replacementProp =
            _directoryStaticProperties[node.propertyName.name];
        if (replacementProp != null) {
          return '$fsAccess.$replacementProp';
        }
      }
    }

    return null;
  }

  /// Returns the `dart:io` type name (`'File'`, `'Directory'`,
  /// `'FileSystemEntity'`, or `'Link'`) if [node] is a flagged call or property
  /// access, or `null` otherwise.
  static String? targetNameForCallOrAccess(AstNode node) {
    if (_isInsideComment(node)) {
      return null;
    }
    final unit = node.thisOrAncestorOfType<CompilationUnit>();

    if (node is InstanceCreationExpression) {
      final constructorName = node.constructorName;
      final typeName = constructorName.type.name.lexeme;
      if (!_constructibleTypeNames.contains(typeName)) {
        return null;
      }
      final ctorName = constructorName.name?.name;
      if (ctorName != null && !_factoryConstructorNames.contains(ctorName)) {
        return null;
      }
      if (node.argumentList.arguments.length != 1) {
        return null;
      }
      final element =
          constructorName.element?.enclosingElement ??
          constructorName.type.element;
      if (element != null) {
        return _isDartIoOrPackageFileElement(element) ? typeName : null;
      }
      if (unit != null &&
          _hasActiveIoOrFileImport(
            unit,
            prefix: constructorName.type.importPrefix?.name.lexeme,
            symbolName: typeName,
          )) {
        return typeName;
      }
      return null;
    }

    if (node is MethodInvocation) {
      final target = node.target;
      final methodName = node.methodName.name;

      // Unprefixed `File(path)`, `Directory(path)`, `Link(path)`
      if (target == null) {
        if (!_constructibleTypeNames.contains(methodName) ||
            node.argumentList.arguments.length != 1) {
          return null;
        }
        final element = node.methodName.element;
        if (element != null) {
          if (element is! InterfaceElement &&
              element is! ConstructorElement &&
              element is! TypeAliasElement) {
            return null;
          }
          return _isDartIoOrPackageFileElement(element) ? methodName : null;
        }
        if (unit != null &&
            _hasActiveIoOrFileImport(unit, symbolName: methodName)) {
          return methodName;
        }
        return null;
      }

      // Prefixed `io.File(path)` / `io.Directory(path)`
      if (target is SimpleIdentifier &&
          _constructibleTypeNames.contains(methodName) &&
          node.argumentList.arguments.length == 1) {
        final targetElement = target.element;
        if (targetElement != null && targetElement is! PrefixElement) {
          return null;
        }
        final methodElement = node.methodName.element;
        if (methodElement != null) {
          return _isDartIoOrPackageFileElement(methodElement)
              ? methodName
              : null;
        }
        if (unit != null &&
            _hasActiveIoOrFileImport(
              unit,
              prefix: target.name,
              symbolName: methodName,
            )) {
          return methodName;
        }
        return null;
      }

      // Named factory `File.fromUri(uri)`, `Directory.fromRawPath(raw)`, etc.
      final targetType = _extractTargetTypeName(target);
      if (targetType != null && _constructibleTypeNames.contains(targetType)) {
        if (_factoryConstructorNames.contains(methodName) &&
            node.argumentList.arguments.length == 1) {
          if (_isTargetDartIoOrPackageFile(target, unit, targetType)) {
            return targetType;
          }
        }
      }

      // Static method on `FileSystemEntity`
      if (targetType == 'FileSystemEntity' &&
          _entityStaticMethods.contains(methodName)) {
        if (_isTargetDartIoOrPackageFile(target, unit, targetType!)) {
          return targetType;
        }
      }
      return null;
    }

    if (node is PrefixedIdentifier) {
      final parent = node.parent;
      if (parent is ConstructorName ||
          parent is NamedType ||
          parent is MethodInvocation ||
          parent is PropertyAccess ||
          parent is InstanceCreationExpression ||
          parent is ConstructorReference) {
        return null;
      }
      if (node.prefix.name == 'Directory' &&
          _directoryStaticProperties.containsKey(node.identifier.name)) {
        if (_isTargetDartIoOrPackageFile(node.prefix, unit, 'Directory')) {
          return 'Directory';
        }
      }
      return null;
    }

    if (node is PropertyAccess) {
      final parent = node.parent;
      if (parent is MethodInvocation && parent.target == node) {
        return null;
      }
      final target = node.target;
      if (target != null &&
          _extractTargetTypeName(target) == 'Directory' &&
          _directoryStaticProperties.containsKey(node.propertyName.name)) {
        if (_isTargetDartIoOrPackageFile(target, unit, 'Directory')) {
          return 'Directory';
        }
      }
      return null;
    }

    return null;
  }

  static String? _extractPrefixName(Expression target) {
    if (target is PrefixedIdentifier) {
      return target.prefix.name;
    }
    return null;
  }

  static String? _extractTargetTypeName(Expression target) {
    if (target is SimpleIdentifier) {
      if (targetTypeNames.contains(target.name)) {
        return target.name;
      }
    } else if (target is PrefixedIdentifier) {
      if (targetTypeNames.contains(target.identifier.name)) {
        return target.identifier.name;
      }
    }
    return null;
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

  static bool _hasActiveDartIoImportFor(
    CompilationUnit unit, {
    String? prefix,
    required String symbolName,
  }) {
    var hasDartIo = false;
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == 'package:file/file.dart' && prefix == null) {
        return false;
      }
      if (uri != 'dart:io') {
        continue;
      }
      final directivePrefix = directive.prefix?.name;
      if (directivePrefix != prefix) {
        continue;
      }
      if (_isSymbolVisibleInImport(directive, symbolName)) {
        hasDartIo = true;
      }
    }
    return hasDartIo;
  }

  static bool _hasActiveIoOrFileImport(
    CompilationUnit unit, {
    String? prefix,
    required String symbolName,
  }) {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri != 'dart:io' && uri != 'package:file/file.dart') {
        continue;
      }
      final directivePrefix = directive.prefix?.name;
      if (directivePrefix != prefix) {
        continue;
      }
      if (_isSymbolVisibleInImport(directive, symbolName)) {
        return true;
      }
    }
    return false;
  }

  static bool _isDartIoElement(Element element) {
    final library = element.library;
    if (library == null) {
      return false;
    }
    final uri = library.uri.toString();
    return uri == 'dart:io' || uri.startsWith('dart:_');
  }

  static bool _isDartIoOrPackageFileElement(Element element) {
    if (_isDartIoElement(element)) {
      return true;
    }
    final library = element.library;
    if (library == null) {
      return false;
    }
    final uri = library.uri;
    return uri.scheme == 'package' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'file';
  }

  static bool _isInsideComment(AstNode node) =>
      node.thisOrAncestorOfType<Comment>() != null ||
      node.thisOrAncestorOfType<CommentReference>() != null;

  static bool _isSymbolVisibleInImport(
    ImportDirective directive,
    String symbolName,
  ) {
    for (final combinator in directive.combinators) {
      if (combinator is HideCombinator) {
        if (combinator.hiddenNames.any((id) => id.name == symbolName)) {
          return false;
        }
      } else if (combinator is ShowCombinator) {
        if (!combinator.shownNames.any((id) => id.name == symbolName)) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _isTargetDartIoOrPackageFile(
    Expression target,
    CompilationUnit? unit,
    String targetType,
  ) {
    Element? element;
    if (target is SimpleIdentifier) {
      element = target.element;
    } else if (target is PrefixedIdentifier) {
      element = target.identifier.element;
    }
    if (element != null) {
      return _isDartIoOrPackageFileElement(element);
    }
    if (unit != null) {
      return _hasActiveIoOrFileImport(
        unit,
        prefix: _extractPrefixName(target),
        symbolName: targetType,
      );
    }
    return false;
  }

  static String? _methodForConstructibleType(String typeName) =>
      switch (typeName) {
        'Directory' => 'directory',
        'File' => 'file',
        'Link' => 'link',
        _ => null,
      };

  static String _modType(Expression target, String methodName) {
    if (_constructibleTypeNames.contains(methodName)) {
      return methodName;
    }
    return _extractTargetTypeName(target) ?? '';
  }

  static bool _parenthesizedConstructorOrFactory(
    Expression target,
    String methodName,
  ) {
    if (_constructibleTypeNames.contains(methodName) &&
        target is SimpleIdentifier) {
      return true;
    }
    return _factoryConstructorNames.contains(methodName);
  }

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
    registry.addNamedType(this, visitor);
    registry.addPrefixedIdentifier(this, visitor);
    registry.addPropertyAccess(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final UseFileSystem rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final targetName = UseFileSystem.targetNameForCallOrAccess(node);
    if (targetName != null) {
      rule.reportAtNode(node, arguments: [targetName]);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final targetName = UseFileSystem.targetNameForCallOrAccess(node);
    if (targetName != null) {
      rule.reportAtNode(node, arguments: [targetName]);
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (UseFileSystem.isFileSystemNamedType(node)) {
      rule.reportAtNode(node, arguments: [node.name.lexeme]);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final targetName = UseFileSystem.targetNameForCallOrAccess(node);
    if (targetName != null) {
      rule.reportAtNode(node, arguments: [targetName]);
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final targetName = UseFileSystem.targetNameForCallOrAccess(node);
    if (targetName != null) {
      rule.reportAtNode(node, arguments: [targetName]);
    }
  }
}
