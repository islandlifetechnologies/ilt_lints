Lint rules: [lints.ilt.run](https://lints.ilt.run)

## Usage:

**analysis_options.yaml**

```yaml
# Optional; you can also use your own rules rather than importing the recommended ones.
include: package:ilt_lints/lints.yaml

# Optional plugins; already included if you use the recommended rules above
plugins:
  ilt_lints:
    version: ^2.0.0
    diagnostics:
      avoid_large_ccn: true
      export_library: true
      prefer_const_constructors: true
      prefer_named_parameters: true
      prefer_primary_constructors: true
      sort_fields: true
      sort_functions_by_scope: true
      sort_functions_alphabetically: true
      sort_named_parameters: true
      sort_widget_functions: true
      sort_widget_parameters: true
      use_clock: true
      use_file_system: true
      valid_json_serializable: true

# Optional; configuration values for the avoid_large_ccn rule
avoid_large_ccn:
  ccn: 20

# Optional; configuration values for the export_library rule
export_library:
  - exporter: lib/my_package.dart
    include:
      - src/**/*.dart
    exclude:
      - "**/g.dart"
      - "**/freezed.dart"

# Optional; configuration values for the prefer_named_parameters rule
prefer_named_parameters:
  count: 2

# Optional; configuration values for the sort_fields rule
sort_fields:
  final_first: true

# Optional; configuration values for the sort_named_parameters rule
sort_named_parameters:
  required_first: false
  ignore:
    - key
    - child
```

**pubspec.yaml**

```yaml
dev_dependencies:
  ilt_lints: <<version>
```

## CLI Fix Tool

To apply automated fixes for all enabled custom `ilt_lints` rules across your project:

```sh
dart run ilt_lints:fix
```

You can also pass specific file or directory paths, or `--dry-run` (`-n`) to preview fixes without modifying files:

```sh
dart run ilt_lints:fix --dry-run lib/
```

## Custom Lint Rules

### `avoid_large_ccn`

Calculates the [cyclomatic complexity](https://en.wikipedia.org/wiki/Cyclomatic_complexity) number (CCN) for every function, method, and constructor and triggers when the complexity exceeds the configured `ccn` threshold (defaults to `20`).

Supports a custom `ccn` option in `analysis_options.yaml` (defaults to `20`):

```yaml
avoid_large_ccn:
  ccn: 20
```

### `export_library`

Ensures all files matching any `include` glob (and not matching any optional `exclude` glob) for a configured `exporter` file are exported by that exporter. If a file overlaps `include` and `exclude`, `exclude` wins.

Supports a list of options in `analysis_options.yaml`:

- `exporter`: The path of the file that has the exports.
- `include`: List of glob definitions of the files to scan and make sure they are exported by the exporter.
- `exclude`: Optional list of glob definitions of files to exclude from the exporter.

If no options are passed in, defaults to:

```yaml
export_library:
  - exporter: lib/${packageName}.dart
    include:
      - src/**/*.dart
    exclude:
      - "**/g.dart"
      - "**/freezed.dart"
```

Includes an automated quick fix (`Export missing library files`).

### `prefer_const_constructors`

Detects classes whose constructor (primary constructor or generative constructor) can be marked `const` without any other changes and flags them if not already marked `const`.

Includes an automated quick fix (`Add const modifier to constructor`) that adds `const` to the primary constructor (`class const Foo(...)`) or generative constructor (`const Foo(...);`).

### `prefer_named_parameters`

Triggers when a function, method, or constructor declares more than `count` positional parameters (defaults to `2`).

Supports a custom `count` option in `analysis_options.yaml` (defaults to `2`):

```yaml
prefer_named_parameters:
  count: 2
```

Includes an automated quick fix (`Convert to named parameters`) that converts all parameters in the function, method, or constructor to named parameters.

### `prefer_primary_constructors`

Detects classes that do not use a Dart primary constructor (`class Foo(...)` or `class const Foo(...)`).

Includes an automated quick fix (`Convert to primary constructor`) that:

- Adds `()` to classes with no constructors (`class Foo()`).
- Moves generative constructors to the class header (`class Foo(...)`, `class const Foo(...)`, `class Foo.named(...)`).
- Merges `this.<field>` parameters with their corresponding instance field declarations into declaring parameters (`final Type field` / `var Type field`), preserving annotations, default values, and doc comments.
- Converts any constructor initializer list or non-empty constructor body into a `this : ...;` / `this { ... }` primary constructor body inside the class.

### `sort_fields`

Ensures fields within a type body (classes, mixins, enums, extensions, and extension types) appear before all methods, getters, setters, and operators (ignoring constructors), grouped by scope in the following order and sorted alphabetically within each group:

1. Public `static const` fields
2. Private `static const` fields
3. Public `static` fields
4. Private `static` fields
5. Public instance fields
6. Private instance fields

Supports a custom `final_first` option in `analysis_options.yaml` (defaults to `true`):

- When `true`, `final` fields are grouped above non-`final` fields within each scope, and each subgroup is sorted alphabetically.
- When `false`, all fields within a scope are sorted alphabetically regardless of `final`.

```yaml
sort_fields:
  final_first: true
```

Includes an automated quick fix (`Sort fields`).

### `sort_functions_by_scope`

Ensures functions, getters, and setters within a type body (classes, mixins, enums, extensions, and extension types) are sorted by scope in the following order:

1. Public static getters
2. Public static setters
3. Public static functions
4. Private static getters
5. Private static setters
6. Private static functions
7. Public getters
8. Public setters
9. Private getters
10. Private setters
11. Public instance functions
12. Private instance functions

Fields, constructors, and operators are ignored. When `sort_widget_functions` is enabled on a `Widget` or `State` class, functions owned by `sort_widget_functions` (`initState`, `didChangeDependencies`, `didUpdateWidget`, `deactivate`, `dispose`, `build*`, `_build*`, and `build`) are deferred to `sort_widget_functions`. Includes an automated quick fix (`Sort functions by scope`).

### `sort_functions_alphabetically`

Ensures functions, getters, and setters within a type body are sorted alphabetically (lexicographically) within each scope (e.g., all public static getters alphabetically, all public static setters alphabetically, all public static functions alphabetically, etc.).

Fields, constructors, and operators are ignored. When `sort_widget_functions` is enabled on a `Widget` or `State` class, functions owned by `sort_widget_functions` (`initState`, `didChangeDependencies`, `didUpdateWidget`, `deactivate`, `dispose`, `build*`, `_build*`, and `build`) are deferred to `sort_widget_functions`. Includes an automated quick fix (`Sort functions alphabetically`).

### `sort_named_parameters`

Ensures named parameters in function/method/constructor declarations and named arguments when calling a function/method/constructor are sorted alphabetically. Leading underscores on private named parameters (such as `this._foo` or `required String _foo`) are ignored when sorting so `_foo` sorts as `foo`.

Supports custom options in `analysis_options.yaml`:

- `required_first` (defaults to `false`): when `true`, sorts `required` named parameters alphabetically before optional named parameters in declarations.
- `ignore`: a list of parameter names (e.g., `ignore: [key, child]`) that should be skipped during sorting and quick fixes.

```yaml
sort_named_parameters:
  required_first: true
  ignore:
    - key
    - child
```

Includes an automated quick fix (`Sort named parameters alphabetically`).

### `sort_widget_parameters`

Ensures the `child`, `children`, `builder`, and `itemBuilder` named parameters of a `Widget` constructor (and the matching named arguments of widget constructor invocations) come after all other named parameters, sorted alphabetically among themselves. When enabled, this rule takes priority over `sort_named_parameters` for these parameters. Includes an automated quick fix (`Move widget child and builder parameters to the end`).

### `sort_widget_functions`

Ensures functions within a `Widget` or `State` subclass are sorted in lifecycle and build order:

1. `initState`
2. `didChangeDependencies`
3. `didUpdateWidget`
4. `deactivate`
5. `dispose`
6. Other functions, getters, and setters (sorted by `sort_functions_by_scope` and `sort_functions_alphabetically` when enabled)
7. Public functions prefixed with `build` (`build*`)
8. Private functions prefixed with `_build` (`_build*`)
9. `build`

Classes that do not extend or implement `Widget` or `State` are ignored. Includes an automated quick fix (`Sort widget functions`).

### `use_clock`

Detects usages of `DateTime.now()` and `DateTime.now` tear-offs in files inside the `lib/` folder (ignoring files in `test/` and other non-`lib/` directories) and requires using `clock.now()` / `clock.now` from `package:clock/clock.dart` instead so that time can be mocked in tests.

Includes an automated quick fix (`Replace with clock.now`) that replaces `DateTime.now()` with `clock.now()` (or `DateTime.now` with `clock.now`) and automatically adds `import 'package:clock/clock.dart';` if not already imported.

### `use_file_system`

Detects direct usages of `dart:io` `File`, `Directory`, `FileSystemEntity`, and `Link` (including `Directory.current` and `Directory.systemTemp`) in files inside the `lib/` folder (ignoring files in `test/` and other non-`lib/` directories) and requires using `fs` from `package:io_ext/io_ext.dart` (a `FileSystem` from `package:file/file.dart`) so file system operations can be overridden with `withFileSystem` in tests.

Includes an automated quick fix (`Use fs from package:io_ext`) that:

- Rewrites `File(...)`, `Directory(...)`, `Link(...)`, `Directory.current`, `Directory.systemTemp`, and `FileSystemEntity` static methods to use `fs` (`fs.file(...)`, `fs.directory(...)`, `fs.link(...)`, `fs.currentDirectory`, `fs.systemTempDirectory`, etc.).
- Automatically updates `dart:io` (removing it or hiding `File`, `Directory`, `FileSystemEntity`, and `Link` when other `dart:io` symbols are still used), adds `package:io_ext/io_ext.dart`, and adds `package:file/file.dart` when `File`, `Directory`, `FileSystemEntity`, or `Link` types are still referenced.

### `valid_json_serializable`

Ensures classes annotated with `@JsonSerializable` have the generated `part` directive and valid generated helper call methods:

1. Ensures `part '<filename>.g.dart';` exists in the file when `createFactory` or `createToJson` is enabled.
2. If `createFactory` is `true` (or not explicitly `false`), ensures a factory constructor or static function named `fromJson` exists and calls the generated `_$<ClassName>FromJson` function.
3. If `createToJson` is `true` (or not explicitly `false`), ensures a `toJson` instance method exists and calls the generated `_$<ClassName>ToJson` function.

Includes an automated quick fix (`Add valid fromJson and/or toJson`) that adds the `part '<filename>.g.dart';` directive and generates `factory <ClassName>.fromJson(...)` and `toJson()` methods (including converting an empty `;` class body to `{ ... }`). Runs with `dart run ilt_lints:fix`.
