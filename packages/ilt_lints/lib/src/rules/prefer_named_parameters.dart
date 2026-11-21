import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

/// Resolved custom configuration options for [PreferNamedParameters].
class const PreferNamedParametersOptions({final int count = 2}) {}

/// A lint rule that triggers when a function, method, or constructor has more
/// than [count] positional parameters (defaulting to `2`).
///
/// Supports custom configuration in `analysis_options.yaml`:
/// ```yaml
/// prefer_named_parameters:
///   count: 2
/// ```
class PreferNamedParameters({final int? count}) extends AnalysisRule {
  this
    : super(
        description:
            'Prefer named parameters when a function has more than the '
            'configured number of positional parameters.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'prefer_named_parameters',
    'Prefer named parameters when a function has more than {0} positional '
        'parameters.',
    correctionMessage:
        'Try converting positional parameters to named parameters.',
  );

  /// The default maximum number of positional parameters allowed before the
  /// lint triggers.
  static const defaultCount = 2;

  /// Reads the configured [PreferNamedParametersOptions] (`count`) for
  /// `prefer_named_parameters` from `analysis_options.yaml` starting from
  /// [startFile] or [optionsFile].
  static PreferNamedParametersOptions readOptions(
    File? startFile, {
    File? optionsFile,
  }) {
    final resolvedOptionsFile = optionsFile ?? _findOptionsFile(startFile);
    if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
      return const PreferNamedParametersOptions();
    }
    try {
      final content = resolvedOptionsFile.readAsStringSync();
      final root = loadYamlNode(content);
      if (root is! YamlMap) {
        return const PreferNamedParametersOptions();
      }
      var countResult = defaultCount;

      void collect(Object? node) {
        if (node is! YamlMap) {
          return;
        }
        if (node['count'] case final int value) {
          countResult = value;
        }
      }

      collect(root['prefer_named_parameters']);

      final iltLints = root['ilt_lints'];
      if (iltLints is YamlMap) {
        collect(iltLints['prefer_named_parameters']);
        final rules = iltLints['rules'];
        if (rules is YamlMap) {
          collect(rules['prefer_named_parameters']);
        }
      }

      final plugins = root['plugins'];
      if (plugins is YamlMap) {
        final pluginConfig = plugins['ilt_lints'];
        if (pluginConfig is YamlMap) {
          collect(pluginConfig['prefer_named_parameters']);
          final diagnostics = pluginConfig['diagnostics'];
          if (diagnostics is YamlMap) {
            collect(diagnostics['prefer_named_parameters']);
          }
        }
      }

      final linter = root['linter'];
      if (linter is YamlMap) {
        final rules = linter['rules'];
        if (rules is YamlMap) {
          collect(rules['prefer_named_parameters']);
        }
      }

      return PreferNamedParametersOptions(count: countResult);
    } on Object {
      return const PreferNamedParametersOptions();
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
    final effectiveCount = count ?? fileOptions.count;
    final visitor = _Visitor(this, count: effectiveCount);
    registry.addFormalParameterList(this, visitor);
  }
}

class const _Visitor(
  final PreferNamedParameters rule, {
  required final int count,
}) extends SimpleAstVisitor<void> {
  @override
  void visitFormalParameterList(FormalParameterList node) {
    // Function types (typedefs) and anonymous functions are constrained by
    // their context, so they are not flagged.
    final parent = node.parent;
    if (parent is GenericFunctionType || parent is FunctionTypeAlias) {
      return;
    }
    if (parent is FunctionExpression &&
        parent.parent is! FunctionDeclaration &&
        parent.parent is! MethodDeclaration) {
      return;
    }
    final positionalCount = node.parameters.where((p) => p.isPositional).length;
    if (positionalCount > count) {
      rule.reportAtNode(node, arguments: [count.toString()]);
    }
  }
}
