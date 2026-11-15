# jaspr_lint_builder

A Dart website builder and schema validator powered by the [Jaspr](https://pub.dev/packages/jaspr) framework, [`json_schema`](https://pub.dev/packages/json_schema), and [`yaon`](https://pub.dev/packages/yaon). It validates custom lint YAML specifications against `assets/lint_schema.yaml` and generates static documentation pages (HTML, CSS, and JS).

The visual design and layout are modeled after the official Dart Linter Rules documentation:
- [All Linter Rules (`https://dart.dev/tools/linter-rules`)](https://dart.dev/tools/linter-rules)
- [Individual Linter Rule (`https://dart.dev/tools/linter-rules/avoid_print`)](https://dart.dev/tools/linter-rules/avoid_print)

## Installation & Activation

### Adding to `pubspec.yaml`

Add `jaspr_lint_builder` to your package's `dev_dependencies`:

```yaml
dev_dependencies:
  jaspr_lint_builder: ^1.0.0
```

Then fetch dependencies:

```sh
dart pub get
```

### Global Activation

You can also activate `jaspr_lint_builder` globally using `dart pub global activate`:

```sh
# Activate from pub.dev
dart pub global activate jaspr_lint_builder

# Or activate from a local path checkout
dart pub global activate --source path packages/jaspr_lint_builder
```

## CLI Scripts (`bin/validate.dart` and `bin/build.dart`)

The package provides two CLI executables in `bin/`:

1. **`validate`** (`bin/validate.dart`) — Validates a custom lints YAML file against `assets/lint_schema.yaml` without building the documentation site, exiting with a non-zero exit code if validation fails.
2. **`build`** (`bin/build.dart`) — Validates a custom lints YAML file against `assets/lint_schema.yaml` and builds the static Jaspr documentation site (HTML, CSS, and JS) using the `title` and `lints` defined in the YAML file.

### 1. Validating a Lints YAML File (`validate`)

Using `dart pub run` from a project that depends on `jaspr_lint_builder`:

```sh
dart pub run jaspr_lint_builder:validate --input ../ilt_lints/assets/lints.yaml
```

Or when globally activated with `dart pub global activate`:

```sh
dart pub global run jaspr_lint_builder:validate --input ../ilt_lints/assets/lints.yaml
```

You can also pass a custom schema path if needed:

```sh
dart pub run jaspr_lint_builder:validate \
  --input path/to/lints.yaml \
  --schema assets/lint_schema.yaml
```

`validate` options:
- `-i, --input`: Path to the input `lints.yaml` file (defaults to `../ilt_lints/assets/lints.yaml`).
- `-s, --schema`: Optional path to a custom `lint_schema.yaml` file (defaults to the package's bundled `assets/lint_schema.yaml`).
- `-h, --help`: Display usage information.

Exits with `0` when valid and a non-zero exit code (`65` for invalid YAML/schema violations, `66` if the input file does not exist, `64` for invalid CLI usage) when validation fails.

### 2. Building the Documentation Website (`build`)

Using `dart pub run` from a project that depends on `jaspr_lint_builder`:

```sh
dart pub run jaspr_lint_builder:build \
  --favicon ../ilt_lints/assets/favicon.png \
  --input ../ilt_lints/assets/lints.yaml \
  --output build/web
```

Or when globally activated with `dart pub global activate`:

```sh
dart pub global run jaspr_lint_builder:build \
  --favicon ../ilt_lints/assets/favicon.png \
  --input ../ilt_lints/assets/lints.yaml \
  --output build/web
```

`build` options:
- `-f, --favicon`: Optional path to a `.png` image file used to generate site favicons (`favicon.ico`, `favicon-16x16.png`, `favicon-32x32.png`, `favicon-48x48.png`, `apple-touch-icon.png`, `favicon-192x192.png`, `favicon-512x512.png`).
- `-i, --input`: Path to the input `lints.yaml` file matching `lint_schema.yaml` (defaults to `../ilt_lints/assets/lints.yaml`).
- `-o, --output`: Output directory for generated HTML, CSS, and JS files (defaults to `build/web`).
- `-s, --schema`: Optional path to a custom `lint_schema.yaml` file.
- `-h, --help`: Display usage information.

## Programmatic Usage

Both the schema validator and site builder are exported from `package:jaspr_lint_builder/jaspr_lint_builder.dart`.

### Validating a `lints.yaml` File Externally

```dart
import 'package:jaspr_lint_builder/jaspr_lint_builder.dart';

void main() {
  const validator = LintSchemaValidator();

  // Returns ValidationResults from package:json_schema
  final results = validator.validateFile('../ilt_lints/assets/lints.yaml');
  if (!results.isValid) {
    for (final error in results.errors) {
      print('Validation error: $error');
    }
  }

  // Or throw a FormatException if invalid:
  validator.assertValidFile('../ilt_lints/assets/lints.yaml');
}
```

### Building the Static Site Programmatically

```dart
import 'package:jaspr_lint_builder/jaspr_lint_builder.dart';

Future<void> main() async {
  const builder = JasprLintSiteBuilder();
  final result = await builder.buildFromYamlFile(
    outputDirectoryPath: 'build/web',
    yamlFilePath: '../ilt_lints/assets/lints.yaml',
  );
  print('Generated ${result.generatedFiles.length} files for ${result.title}!');
}
```

## Serving the Example Website with Shelf

From `packages/jaspr_lint_builder/example`, run `bin/serve.dart` to build the website from `ilt_lints/assets/lints.yaml` and serve it locally via `shelf`:

```sh
dart pub run bin/serve.dart --port 8080
```

## Generated Output Structure

- `index.html` & `linter-rules/index.html` — Searchable and filterable directory of all custom lints (`All` vs `Fix available`).
- `linter-rules/<rule_name>.html` & `linter-rules/<rule_name>/index.html` — Individual rule pages featuring status and quick-fix badges, **DO** guidelines, `BAD:` and `GOOD:` Dart examples, and `analysis_options.yaml` instructions.
- `styles.css` — Responsive light/dark stylesheet matching `dart.dev`.
- `main.js` — Client-side interactivity (live rule search, quick-fix filter chips, copy-to-clipboard buttons, light/dark theme toggle, and syntax highlighting).
