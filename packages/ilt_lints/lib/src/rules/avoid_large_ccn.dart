import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

/// Resolved custom configuration options for [AvoidLargeCcn].
class const AvoidLargeCcnOptions({final int ccn = AvoidLargeCcn.defaultCcn}) {}

/// A lint rule that triggers when a function's cyclomatic complexity number
/// (CCN) exceeds the configured [ccn] threshold (defaulting to `20`).
///
/// Supports custom configuration in `analysis_options.yaml`:
/// ```yaml
/// avoid_large_ccn:
///   ccn: 20
/// ```
class AvoidLargeCcn({final int? ccn}) extends AnalysisRule {
  this
    : super(
        description:
            'Avoid functions with a cyclomatic complexity number (CCN) larger '
            'than the configured threshold.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'avoid_large_ccn',
    'Cyclomatic complexity number ({0}) exceeds the maximum allowed ({1}).',
    correctionMessage:
        'Try simplifying the function or extracting smaller helper functions.',
  );

  /// The default maximum cyclomatic complexity number allowed before the lint
  /// triggers.
  static const defaultCcn = 20;

  /// Calculates the cyclomatic complexity number (CCN) for a [FunctionBody].
  ///
  /// Starts at a base complexity of `1` and increments for each decision point
  /// (`if`, `for`, `while`, `do`, `case`, `catch`, `?:`, `&&`, `||`, `??`,
  /// `??=`, and logical pattern operators).
  static int calculateComplexity(FunctionBody body) {
    final visitor = _CcnVisitor();
    body.accept(visitor);
    return visitor.complexity;
  }

  /// Reads the configured [AvoidLargeCcnOptions] (`ccn`) for `avoid_large_ccn`
  /// from `analysis_options.yaml` starting from [startFile] or [optionsFile].
  static AvoidLargeCcnOptions readOptions(
    File? startFile, {
    File? optionsFile,
  }) {
    final resolvedOptionsFile = optionsFile ?? _findOptionsFile(startFile);
    if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
      return const AvoidLargeCcnOptions();
    }
    try {
      final content = resolvedOptionsFile.readAsStringSync();
      final root = loadYamlNode(content);
      if (root is! YamlMap) {
        return const AvoidLargeCcnOptions();
      }
      var ccnResult = defaultCcn;

      void collect(Object? node) {
        if (node is! YamlMap) {
          return;
        }
        if (node['ccn'] case final int value) {
          ccnResult = value;
        }
      }

      collect(root['avoid_large_ccn']);

      final iltLints = root['ilt_lints'];
      if (iltLints is YamlMap) {
        collect(iltLints['avoid_large_ccn']);
        final rules = iltLints['rules'];
        if (rules is YamlMap) {
          collect(rules['avoid_large_ccn']);
        }
      }

      final plugins = root['plugins'];
      if (plugins is YamlMap) {
        final pluginConfig = plugins['ilt_lints'];
        if (pluginConfig is YamlMap) {
          collect(pluginConfig['avoid_large_ccn']);
          final diagnostics = pluginConfig['diagnostics'];
          if (diagnostics is YamlMap) {
            collect(diagnostics['avoid_large_ccn']);
          }
        }
      }

      final linter = root['linter'];
      if (linter is YamlMap) {
        final rules = linter['rules'];
        if (rules is YamlMap) {
          collect(rules['avoid_large_ccn']);
        }
      }

      return AvoidLargeCcnOptions(ccn: ccnResult);
    } on Object {
      return const AvoidLargeCcnOptions();
    }
  }

  static File? _findOptionsFile(File? startFile) {
    var folder = startFile?.parent;
    while (folder != null) {
      final candidate = folder.getFile('analysis_options.yaml');
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
    final fileOptions = readOptions(
      context.definingUnit.file,
      optionsFile: optionsFile,
    );
    final effectiveCcn = ccn ?? fileOptions.ccn;
    final visitor = _Visitor(this, maxCcn: effectiveCcn);
    registry.addConstructorDeclaration(this, visitor);
    registry.addFunctionDeclaration(this, visitor);
    registry.addMethodDeclaration(this, visitor);
    registry.addPrimaryConstructorBody(this, visitor);
  }
}

class _CcnVisitor() extends RecursiveAstVisitor<void> {
  var complexity = 1;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.operator.type == TokenType.QUESTION_QUESTION_EQ) {
      complexity++;
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final operatorType = node.operator.type;
    if (operatorType == TokenType.AMPERSAND_AMPERSAND ||
        operatorType == TokenType.BAR_BAR ||
        operatorType == TokenType.QUESTION_QUESTION) {
      complexity++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Nested named functions are evaluated independently by their own
    // `visitFunctionDeclaration` hook.
  }

  @override
  void visitIfElement(IfElement node) {
    complexity++;
    super.visitIfElement(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    super.visitIfStatement(node);
  }

  @override
  void visitLogicalAndPattern(LogicalAndPattern node) {
    complexity++;
    super.visitLogicalAndPattern(node);
  }

  @override
  void visitLogicalOrPattern(LogicalOrPattern node) {
    complexity++;
    super.visitLogicalOrPattern(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    complexity++;
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    complexity++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }
}

class const _Visitor(final AvoidLargeCcn rule, {required final int maxCcn})
    extends SimpleAstVisitor<void> {
  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final body = node.body;
    if (body is EmptyFunctionBody) {
      return;
    }
    final complexity = AvoidLargeCcn.calculateComplexity(body);
    if (complexity > maxCcn) {
      if (node.name != null) {
        rule.reportAtToken(
          node.name!,
          arguments: [complexity.toString(), maxCcn.toString()],
        );
      } else if (node.typeName != null) {
        rule.reportAtNode(
          node.typeName!,
          arguments: [complexity.toString(), maxCcn.toString()],
        );
      } else {
        rule.reportAtNode(
          node,
          arguments: [complexity.toString(), maxCcn.toString()],
        );
      }
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final body = node.functionExpression.body;
    if (body is EmptyFunctionBody) {
      return;
    }
    final complexity = AvoidLargeCcn.calculateComplexity(body);
    if (complexity > maxCcn) {
      rule.reportAtToken(
        node.name,
        arguments: [complexity.toString(), maxCcn.toString()],
      );
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final body = node.body;
    if (body is EmptyFunctionBody) {
      return;
    }
    final complexity = AvoidLargeCcn.calculateComplexity(body);
    if (complexity > maxCcn) {
      rule.reportAtToken(
        node.name,
        arguments: [complexity.toString(), maxCcn.toString()],
      );
    }
  }

  @override
  void visitPrimaryConstructorBody(PrimaryConstructorBody node) {
    final body = node.body;
    if (body is EmptyFunctionBody) {
      return;
    }
    final complexity = AvoidLargeCcn.calculateComplexity(body);
    if (complexity > maxCcn) {
      rule.reportAtToken(
        node.thisKeyword,
        arguments: [complexity.toString(), maxCcn.toString()],
      );
    }
  }
}
