import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

/// Returns `true` if the rule named [ruleName] is enabled in
/// `analysis_options.yaml` starting from [startFile] or [optionsFile].
///
/// Returns `true` when:
/// - No `analysis_options.yaml` exists (default rule set),
/// - the rule is explicitly enabled in `analysis_options.yaml`, or
/// - `package:ilt_lints/lints.yaml` is included (and the rule is not
///   explicitly disabled).
///
/// Returns `false` when the rule is explicitly disabled or when
/// `analysis_options.yaml` configures `ilt_lints` / `linter` rules without
/// including `package:ilt_lints/lints.yaml` or enabling the rule.
bool isIltRuleEnabled(String ruleName, File? startFile, {File? optionsFile}) {
  final resolvedOptionsFile = optionsFile ?? _findOptionsFile(startFile);
  if (resolvedOptionsFile == null || !resolvedOptionsFile.exists) {
    return true;
  }
  try {
    final content = resolvedOptionsFile.readAsStringSync();
    final root = loadYamlNode(content);
    if (root is! YamlMap) {
      return true;
    }
    var hasExplicitRuleConfig = false;
    var includesIltLints = false;
    bool? explicitSetting;

    final includeNode = root['include'];
    if (includeNode is String && includeNode.contains('ilt_lints')) {
      includesIltLints = true;
    } else if (includeNode is YamlList) {
      for (final item in includeNode.nodes) {
        if (item case YamlScalar(value: final String inc)
            when inc.contains('ilt_lints')) {
          includesIltLints = true;
        }
      }
    }

    void checkRuleValue(Object? value) {
      if (value is bool) {
        explicitSetting = value;
      } else if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'ignore' ||
            normalized == 'false' ||
            normalized == 'disable') {
          explicitSetting = false;
        } else if (normalized == 'true' ||
            normalized == 'enable' ||
            normalized == 'info' ||
            normalized == 'warning' ||
            normalized == 'error') {
          explicitSetting = true;
        }
      } else if (value is YamlMap) {
        if (value['enabled'] case final bool enabled) {
          explicitSetting = enabled;
        } else {
          explicitSetting = true;
        }
      }
    }

    void inspectRulesCollection(Object? rulesNode) {
      if (rulesNode is YamlList) {
        hasExplicitRuleConfig = true;
        for (final item in rulesNode.nodes) {
          if (item case YamlScalar(value: final String name)
              when name.toLowerCase() == ruleName) {
            explicitSetting = true;
          }
        }
      } else if (rulesNode is YamlMap) {
        hasExplicitRuleConfig = true;
        for (final entry in rulesNode.entries) {
          final key = entry.key;
          if (key is String && key.toLowerCase() == ruleName) {
            checkRuleValue(entry.value);
          }
        }
      }
    }

    if (root['linter'] case final YamlMap linter) {
      inspectRulesCollection(linter['rules']);
    }

    if (root['ilt_lints'] case final YamlMap iltLints) {
      inspectRulesCollection(iltLints['diagnostics']);
      inspectRulesCollection(iltLints['rules']);
    }

    if (root['plugins'] case final YamlMap plugins) {
      final pluginConfig = plugins['ilt_lints'];
      if (pluginConfig is bool && !pluginConfig) {
        return false;
      } else if (pluginConfig is YamlMap) {
        if (pluginConfig['enabled'] == false) {
          return false;
        }
        inspectRulesCollection(pluginConfig['diagnostics']);
      }
    }

    if (root['analyzer'] case final YamlMap analyzer) {
      if (analyzer['errors'] case final YamlMap errors) {
        for (final entry in errors.entries) {
          final key = entry.key;
          if (key is String && key.toLowerCase() == ruleName) {
            checkRuleValue(entry.value);
          }
        }
      }
    }

    if (explicitSetting != null) {
      return explicitSetting!;
    }
    if (includesIltLints || !hasExplicitRuleConfig) {
      return true;
    }
    return false;
  } on Object {
    return true;
  }
}

File? _findOptionsFile(File? startFile) {
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
