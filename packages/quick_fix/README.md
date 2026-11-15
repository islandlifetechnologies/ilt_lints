A utility library for running automated quick fixes for custom `analysis_server_plugin` / `analyzer` lint rules from the command line, similar to `dart fix --apply`.

> **Note:** `quick_fix` is **not** a standalone CLI tool in and of itself (it does not ship its own `bin/` executable). Instead, it is designed to be wrapped by a custom lint package's own CLI entrypoint, where you register your package's custom lint rules and their corresponding correction producers.

For a complete, real-world example of a package wrapping `quick_fix`, see the [`ilt_lints`](https://pub.dev/packages/ilt_lints) package (specifically `ilt_lints/bin/fix.dart`.

## Installation

Add `quick_fix` to the `dependencies` of your custom lint package's `pubspec.yaml`:

```yaml
dependencies:
  quick_fix: ^1.0.0
```

## How to Wrap `quick_fix` and Register Custom Rules

To expose a quick-fix CLI in your own lint package, create a script in your package's `bin/` directory (for example, `bin/fix.dart`) and pass your custom rules as `RuleFixEntry` instances to `runQuickFixCli`.

### 1. Define `RuleFixEntry` Items for Your Custom Rules

Each `RuleFixEntry` connects three pieces of your custom lint rule:

- `name`: The lowercase diagnostic/rule name (e.g., `MyCustomRule.code.lowerCaseName`).
- `ruleFactory`: A zero-argument factory function returning a new `AnalysisRule` instance (e.g., `MyCustomRule.new`).
- `fixGenerator`: A factory function taking `{required CorrectionProducerContext context}` and returning a `ResolvedCorrectionProducer` (e.g., `MyCustomRuleFix.new`).

### 2. Create Your Wrapper CLI Script (`bin/fix.dart`)

```dart
import 'dart:io';

import 'package:my_custom_lints/my_custom_lints.dart';
import 'package:quick_fix/quick_fix.dart';

Future<void> main(List<String> args) async {
  exitCode = await runQuickFixCli(
    args,
    ruleEntries: [
      RuleFixEntry(
        fixGenerator: MyCustomRuleFix.new,
        name: MyCustomRule.code.lowerCaseName,
        ruleFactory: MyCustomRule.new,
      ),
      RuleFixEntry(
        fixGenerator: AnotherCustomRuleFix.new,
        name: AnotherCustomRule.code.lowerCaseName,
        ruleFactory: AnotherCustomRule.new,
      ),
    ],
  );
}
```

### 3. Running Your Wrapped CLI

Consumers of your lint package can then invoke your wrapper script via `dart run` / `dart pub run`:

```sh
# Apply fixes across the current project
dart pub run my_custom_lints:fix

# Preview fixes without modifying files (dry run)
dart pub run my_custom_lints:fix --dry-run

# Target specific directories or files and exclude specific rules
dart pub run my_custom_lints:fix --path lib --path test --exclude another_custom_rule
```

### Supported CLI Flags Provided by `runQuickFixCli`

| Option / Flag               | Abbr | Default  | Description                                                             |
| :-------------------------- | :--- | :------- | :---------------------------------------------------------------------- |
| `--path`                    | `-p` | `.`      | One or more file or directory paths to analyze and fix.                 |
| `--exclude`                 | `-e` | _(none)_ | Rule names to exclude from being applied.                               |
| `--dry-run`                 | `-n` | `false`  | Compute and report fixes that would be applied without modifying files. |
| `--max-iterations-per-rule` |      | `50`     | Maximum number of fix passes to run per rule on a single file.          |
| `--help`                    | `-h` | `false`  | Display CLI usage information.                                          |

## Programmatic Usage (`FixRunner`)

If you want to invoke the fix engine directly in Dart code or tests without CLI argument parsing, instantiate `FixRunner` directly with your `RuleFixEntry` list:

```dart
import 'package:my_custom_lints/my_custom_lints.dart';
import 'package:quick_fix/quick_fix.dart';

Future<void> main() async {
  final runner = FixRunner(
    dryRun: false,
    ruleEntries: [
      RuleFixEntry(
        fixGenerator: MyCustomRuleFix.new,
        name: MyCustomRule.code.lowerCaseName,
        ruleFactory: MyCustomRule.new,
      ),
    ],
  );

  final FixRunResult result = await runner.run(['lib', 'test']);
  print(
    'Applied ${result.totalFixes} fixes across ${result.totalFilesFixed} files.',
  );
}
```

## Example Usage: `ilt_lints`

See the [`ilt_lints`](../ilt_lints) package in this repository for a full working implementation:

- **CLI wrapper script:** [`packages/ilt_lints/bin/fix.dart`](../ilt_lints/bin/fix.dart) registers all 10 `ilt_lints` rules and their `ResolvedCorrectionProducer` fix generators with `runQuickFixCli`.
- **CLI tests:** [`packages/quick_fix/lib/test/fix_cli_test.dart`](lib/test/fix_cli_test.dart) and [`packages/ilt_lints/test/fix_cli_test.dart`](../ilt_lints/test/fix_cli_test.dart) demonstrate testing custom rules with `runQuickFixCli` and `FixRunner`.
