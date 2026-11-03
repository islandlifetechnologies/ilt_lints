import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

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

/// Resolved custom configuration options for [SortFields].
class SortFieldsOptions {
  const SortFieldsOptions({this.finalFirst = true});

  final bool finalFirst;
}

/// A lint rule that enforces sorting class-level fields above all methods,
/// getters, setters, and operators (ignoring constructors), grouped by
/// [FieldScope] (and with `final` fields before non-`final` fields within each
/// scope when `final_first` is `true`, the default) and sorted alphabetically
/// within each group:
/// 1. Public `static const` fields
/// 2. Private `static const` fields
/// 3. Public `static` fields
/// 4. Private `static` fields
/// 5. Public instance fields
/// 6. Private instance fields
class SortFields extends AnalysisRule {
  SortFields({this.finalFirst})
    : super(
        description: 'Sort fields above methods by scope and alphabetically within each scope.',
        name: code.lowerCaseName,
      );

  static const code = LintCode(
    'sort_fields',
    'Sort {0}.',
    correctionMessage:
        'Try sorting fields by scope and alphabetically above methods.',
  );

  /// Optional override for `final_first`. When `null`, the setting is read from
  /// `analysis_options.yaml` (defaulting to `true`).
  final bool? finalFirst;

  /// Reads the configured [SortFieldsOptions] (`final_first`) for `sort_fields`
  /// from `analysis_options.yaml` starting from [startFile] or [optionsFile].
  static SortFieldsOptions readOptions(File? startFile, {File? optionsFile}) {
    final resolvedOptionsFile = optionsFile ?? _findOptionsFile(startFile);
    if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
      return const SortFieldsOptions();
    }
    try {
      final content = resolvedOptionsFile.readAsStringSync();
      final root = loadYamlNode(content);
      if (root is! YamlMap) {
        return const SortFieldsOptions();
      }
      var finalFirstResult = true;

      void collect(Object? node) {
        if (node is! YamlMap) {
          return;
        }
        if (node['final_first'] case final bool flag) {
          finalFirstResult = flag;
        }
      }

      collect(root['sort_fields']);

      final iltLints = root['ilt_lints'];
      if (iltLints is YamlMap) {
        collect(iltLints['sort_fields']);
        final rules = iltLints['rules'];
        if (rules is YamlMap) {
          collect(rules['sort_fields']);
        }
      }

      final plugins = root['plugins'];
      if (plugins is YamlMap) {
        final pluginConfig = plugins['ilt_lints'];
        if (pluginConfig is YamlMap) {
          collect(pluginConfig['sort_fields']);
          final diagnostics = pluginConfig['diagnostics'];
          if (diagnostics is YamlMap) {
            collect(diagnostics['sort_fields']);
          }
        }
      }

      final linter = root['linter'];
      if (linter is YamlMap) {
        final rules = linter['rules'];
        if (rules is YamlMap) {
          collect(rules['sort_fields']);
        }
      }

      return SortFieldsOptions(finalFirst: finalFirstResult);
    } on Object {
      return const SortFieldsOptions();
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
    final effectiveFinalFirst = finalFirst ?? fileOptions.finalFirst;
    final visitor = _Visitor(this, finalFirst: effectiveFinalFirst);
    registry.addBlockClassBody(this, visitor);
    registry.addBlockEnumBody(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.finalFirst});

  final bool finalFirst;
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
    final seenNonFinalInScope = <FieldScope>{};
    final maxNameByGroup = <(FieldScope, bool), String>{};

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
      final isFinal = member.fields.isFinal;
      final groupKey = (scope, finalFirst && isFinal);

      String? problem;
      if (seenMethod) {
        problem = '${scope.description} before methods';
      } else if (maxScope != null && scope.index < maxScope.index) {
        problem = '${scope.description} before ${maxScope.description}';
      } else if (finalFirst && isFinal && seenNonFinalInScope.contains(scope)) {
        problem =
            'final ${scope.description} before non-final ${scope.description}';
      } else {
        final maxName = maxNameByGroup[groupKey];
        if (maxName != null && name.compareTo(maxName) < 0) {
          problem =
              "${scope.description} alphabetically ('$name' before '$maxName')";
        }
      }

      if (problem != null) {
        rule.reportAtToken(firstVariable.name, arguments: [problem]);
      }

      if (maxScope == null || scope.index >= maxScope.index) {
        maxScope = scope;
      }
      if (finalFirst && !isFinal) {
        seenNonFinalInScope.add(scope);
      }
      final currentMaxName = maxNameByGroup[groupKey];
      if (currentMaxName == null || name.compareTo(currentMaxName) >= 0) {
        maxNameByGroup[groupKey] = name;
      }
    }
  }
}
