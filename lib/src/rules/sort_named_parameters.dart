import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

/// Resolved custom configuration options for [SortNamedParameters].
class SortNamedParametersOptions {
  const SortNamedParametersOptions({
    this.ignore = const {},
    this.requiredFirst = false,
  });

  final Set<String> ignore;
  final bool requiredFirst;
}

/// A lint rule that enforces sorting named parameters alphabetically in both
/// function/constructor declarations ([FormalParameterList]) and call sites
/// ([ArgumentList]).
///
/// Supports custom options in `analysis_options.yaml` (or via the constructor):
/// - `ignore`: a list of parameter names to skip when checking order.
/// - `required_first`: when `true` (defaults to `false`), sorts `required`
///   named parameters alphabetically before optional named parameters in
///   function/constructor declarations.
class SortNamedParameters extends AnalysisRule {
  SortNamedParameters({
    Iterable<String> ignore = const [],
    this.requiredFirst = false,
  })  : ignore = Set<String>.unmodifiable(ignore),
        super(
          name: code.lowerCaseName,
          description:
              'Sort named parameters and arguments alphabetically.',
        );

  static const code = LintCode(
    'sort_named_parameters',
    "Sort named parameters alphabetically ('{0}' before '{1}').",
    correctionMessage: 'Try sorting named parameters alphabetically.',
  );

  /// Parameter names configured directly on this rule instance to ignore.
  final Set<String> ignore;

  /// Whether `required` named parameters must appear before optional named
  /// parameters in declarations.
  final bool requiredFirst;

  /// Strips leading underscores from [name] so private named parameters (such
  /// as `this._foo` or `required String _foo`) are sorted by their public
  /// identifier (`foo`).
  static String normalizeParameterName(String name) {
    final stripped = name.replaceFirst(RegExp('^_+'), '');
    return stripped.isEmpty ? name : stripped;
  }

  /// Reads the configured `ignore` parameter names for `sort_named_parameters`
  /// from `analysis_options.yaml` starting from [startFile] or [optionsFile].
  static Set<String> readIgnoredNames(
    File? startFile, {
    File? optionsFile,
  }) =>
      readOptions(startFile, optionsFile: optionsFile).ignore;

  /// Reads the configured [SortNamedParametersOptions] (`ignore` and
  /// `required_first`) for `sort_named_parameters` from `analysis_options.yaml`
  /// starting from [startFile] or [optionsFile].
  static SortNamedParametersOptions readOptions(
    File? startFile, {
    File? optionsFile,
  }) {
    final resolvedOptionsFile = optionsFile ?? _findOptionsFile(startFile);
    if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
      return const SortNamedParametersOptions();
    }
    try {
      final content = resolvedOptionsFile.readAsStringSync();
      final root = loadYamlNode(content);
      if (root is! YamlMap) {
        return const SortNamedParametersOptions();
      }
      final ignoreResult = <String>{};
      var requiredFirstResult = false;

      void collect(Object? node) {
        if (node is! YamlMap) {
          return;
        }
        final ignoreNode = node['ignore'];
        if (ignoreNode is YamlList) {
          for (final item in ignoreNode.nodes) {
            if (item case YamlScalar(value: final String name)) {
              ignoreResult.add(name);
            }
          }
        }
        if (node['required_first'] case final bool flag) {
          requiredFirstResult = flag;
        }
      }

      collect(root['sort_named_parameters']);

      final iltLints = root['ilt_lints'];
      if (iltLints is YamlMap) {
        collect(iltLints['sort_named_parameters']);
        final rules = iltLints['rules'];
        if (rules is YamlMap) {
          collect(rules['sort_named_parameters']);
        }
      }

      final plugins = root['plugins'];
      if (plugins is YamlMap) {
        final pluginConfig = plugins['ilt_lints'];
        if (pluginConfig is YamlMap) {
          collect(pluginConfig['sort_named_parameters']);
          final diagnostics = pluginConfig['diagnostics'];
          if (diagnostics is YamlMap) {
            collect(diagnostics['sort_named_parameters']);
          }
        }
      }

      final linter = root['linter'];
      if (linter is YamlMap) {
        final rules = linter['rules'];
        if (rules is YamlMap) {
          collect(rules['sort_named_parameters']);
        }
      }

      return SortNamedParametersOptions(
        ignore: ignoreResult,
        requiredFirst: requiredFirstResult,
      );
    } on Object {
      return const SortNamedParametersOptions();
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
      optionsFile =
          context.libraryElement?.session.analysisContext.contextRoot.optionsFile;
    } on Object {
      optionsFile = null;
    }
    final fileOptions = readOptions(
      context.definingUnit.file,
      optionsFile: optionsFile,
    );
    final effectiveIgnore = {
      ...ignore,
      ...fileOptions.ignore,
    };
    final effectiveRequiredFirst = requiredFirst || fileOptions.requiredFirst;
    final visitor = _Visitor(
      this,
      ignoredNames: effectiveIgnore,
      requiredFirst: effectiveRequiredFirst,
    );
    registry.addArgumentList(this, visitor);
    registry.addFormalParameterList(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(
    this.rule, {
    required this.ignoredNames,
    required this.requiredFirst,
  });

  final Set<String> ignoredNames;
  final bool requiredFirst;
  final SortNamedParameters rule;

  @override
  void visitArgumentList(ArgumentList node) {
    String? maxName;
    for (final argument in node.arguments) {
      if (argument is! NamedArgument) {
        continue;
      }
      final nameToken = argument.name;
      final name = nameToken.lexeme;
      if (ignoredNames.contains(name)) {
        continue;
      }
      if (maxName == null || name.compareTo(maxName) >= 0) {
        maxName = name;
      } else {
        rule.reportAtToken(
          nameToken,
          arguments: [name, maxName],
        );
      }
    }
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    String? maxName;
    String? maxRequiredName;
    String? maxOptionalName;
    String? lastOptionalName;

    for (final parameter in node.parameters) {
      if (!parameter.isNamed) {
        continue;
      }
      final nameToken = parameter.name;
      if (nameToken == null) {
        continue;
      }
      final rawName = nameToken.lexeme;
      final name = SortNamedParameters.normalizeParameterName(rawName);
      if (ignoredNames.contains(rawName) || ignoredNames.contains(name)) {
        continue;
      }

      if (!requiredFirst) {
        if (maxName == null || name.compareTo(maxName) >= 0) {
          maxName = name;
        } else {
          rule.reportAtToken(
            nameToken,
            arguments: [name, maxName],
          );
        }
        continue;
      }

      if (parameter.isRequiredNamed) {
        if (lastOptionalName != null) {
          rule.reportAtToken(
            nameToken,
            arguments: [name, lastOptionalName],
          );
        } else if (maxRequiredName != null &&
            name.compareTo(maxRequiredName) < 0) {
          rule.reportAtToken(
            nameToken,
            arguments: [name, maxRequiredName],
          );
        }
        if (maxRequiredName == null ||
            name.compareTo(maxRequiredName) >= 0) {
          maxRequiredName = name;
        }
      } else {
        lastOptionalName = name;
        if (maxOptionalName == null ||
            name.compareTo(maxOptionalName) >= 0) {
          maxOptionalName = name;
        } else {
          rule.reportAtToken(
            nameToken,
            arguments: [name, maxOptionalName],
          );
        }
      }
    }
  }
}
