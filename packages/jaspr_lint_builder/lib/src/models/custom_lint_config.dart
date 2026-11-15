import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:yaon/yaon.dart';

import '../lint_schema_validator.dart';

/// A single custom lint rule definition matching `lint_schema.yaml`.
class const CustomLintRule({
  final String? avoidStatement,
  required final List<String> bad,
  required final String description,
  final String? doStatement,
  required final String enable,
  required final List<String> good,
  required final String name,
  final bool quickFix = false,
  final List<String> tags = const <String>[],
}) {
  /// Parses a [CustomLintRule] from a normalized YAML/JSON `Map<Object?, Object?>`.
  factory CustomLintRule.fromYamlMap(Map<Object?, Object?> map) {
    final name = _requireNonEmptyString(map, 'name');
    final description = _requireNonEmptyString(
      map,
      'description',
      ruleName: name,
    );
    final avoidStatement = _optionalNonEmptyString(
      map,
      'avoid',
      ruleName: name,
    );
    final doStatement = _optionalNonEmptyString(map, 'do', ruleName: name);
    final bad = _requireStringList(map, 'bad', ruleName: name);
    final good = _requireStringList(map, 'good', ruleName: name);
    final enable = _requireNonEmptyString(map, 'enable', ruleName: name);
    final tags = _optionalStringList(map, 'tags', ruleName: name);

    final rawQuickFix = map['quick_fix'];
    final bool quickFix;
    if (rawQuickFix == null) {
      quickFix = false;
    } else if (rawQuickFix is bool) {
      quickFix = rawQuickFix;
    } else {
      throw FormatException(
        "Invalid 'quick_fix' in lint '$name': expected a boolean.",
      );
    }

    const allowedKeys = {
      'avoid',
      'bad',
      'description',
      'do',
      'enable',
      'good',
      'name',
      'quick_fix',
      'tags',
    };
    for (final key in map.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        throw FormatException("Unexpected property '$key' in lint '$name'.");
      }
    }

    return CustomLintRule(
      avoidStatement: avoidStatement,
      bad: List<String>.unmodifiable(bad),
      description: description,
      doStatement: doStatement,
      enable: enable,
      good: List<String>.unmodifiable(good),
      name: name,
      quickFix: quickFix,
      tags: List<String>.unmodifiable(tags),
    );
  }

  static String? _optionalNonEmptyString(
    Map<Object?, Object?> map,
    String key, {
    required String ruleName,
  }) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException(
        "Invalid string property '$key' in lint '$ruleName'.",
      );
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _optionalStringList(
    Map<Object?, Object?> map,
    String key, {
    required String ruleName,
  }) {
    final value = map[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw FormatException(
        "Invalid list property '$key' in lint '$ruleName'.",
      );
    }
    final items = <String>[];
    for (final item in value) {
      if (item is! String || item.trim().isEmpty) {
        throw FormatException(
          "All items in '$key' for lint '$ruleName' must be non-empty strings.",
        );
      }
      items.add(item.trim());
    }
    return items;
  }

  static String _requireNonEmptyString(
    Map<Object?, Object?> map,
    String key, {
    String? ruleName,
  }) {
    final context = ruleName != null ? " in lint '$ruleName'" : '';
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        "Missing or invalid required string property '$key'$context.",
      );
    }
    return value.trim();
  }

  static List<String> _requireStringList(
    Map<Object?, Object?> map,
    String key, {
    required String ruleName,
  }) {
    final value = map[key];
    if (value is! List) {
      throw FormatException(
        "Missing or invalid required list property '$key' in lint '$ruleName'.",
      );
    }
    final items = <String>[];
    for (final item in value) {
      if (item is! String) {
        throw FormatException(
          "All items in '$key' for lint '$ruleName' must be strings.",
        );
      }
      items.add(item.trimRight());
    }
    return items;
  }
}

/// Top-level document containing the site title, optional description, package
/// metadata, and all custom lint rules from a `lints.yaml` file.
class const CustomLintsDocument({
  final String? description,
  required final List<CustomLintRule> lints,
  final String? packageName,
  required final String title,
  final String? version,
}) {
  /// Parses and validates a YAML string against `assets/lint_schema.yaml` using
  /// `yaon` and `json_schema`.
  factory CustomLintsDocument.fromYamlString(
    String yamlContent, {
    FileSystem fs = const LocalFileSystem(),
    String? schemaFilePath,
    String? schemaYamlContent,
  }) {
    final Object? root;
    try {
      root = yaon.parse(yamlContent);
    } on Object catch (error) {
      throw FormatException('Invalid YAML document: $error');
    }

    final validator = LintSchemaValidator(
      fs: fs,
      schemaFilePath: schemaFilePath,
    );
    validator.assertValidData(root, schemaYamlContent: schemaYamlContent);

    if (root is! Map) {
      throw const FormatException(
        'Expected top-level YAML object with "title" and "lints" keys.',
      );
    }

    final rawTitle = root['title'];
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      throw const FormatException(
        'Missing or invalid required top-level "title" string.',
      );
    }
    final title = rawTitle.trim();
    final description = _optionalTopLevelString(root, 'description');
    final packageName = _optionalTopLevelString(root, 'package');
    final version = _optionalTopLevelString(root, 'version');

    final rawLints = root['lints'];
    if (rawLints is! List) {
      throw const FormatException(
        'Missing or invalid required top-level "lints" list.',
      );
    }

    final parsedRules = <CustomLintRule>[];
    for (var i = 0; i < rawLints.length; i++) {
      final node = rawLints[i];
      if (node is! Map) {
        throw FormatException(
          'Expected lint entry at index $i to be a YAML map.',
        );
      }
      parsedRules.add(CustomLintRule.fromYamlMap(node));
    }

    parsedRules.sort((a, b) => a.name.compareTo(b.name));
    return CustomLintsDocument(
      description: description,
      lints: List<CustomLintRule>.unmodifiable(parsedRules),
      packageName: packageName,
      title: title,
      version: version,
    );
  }

  static String? _optionalTopLevelString(
    Map<Object?, Object?> root,
    String key,
  ) {
    final raw = root[key];
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    throw FormatException(
      'Invalid optional top-level "$key": expected a string.',
    );
  }
}

/// Summary of the files generated by `JasprLintSiteBuilder`.
class const LintSiteBuildResult({
  final String? description,
  required final List<String> generatedFiles,
  required final String outputDirectoryPath,
  required final List<CustomLintRule> rules,
  required final String title,
}) {}
