# ilt_lints

**analysis_options.yaml**

```yaml
include: package:ilt_lints/lints.yaml

plugins:
  ilt_lints:
    version: ^2.0.1
    diagnostics:
      sort_fields: true
      sort_functions_by_scope: true
      sort_functions_alphabetically: true
      sort_named_parameters: true

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

## Custom Lint Rules

### `sort_fields`

Ensures fields within a type body (classes, mixins, enums, extensions, and extension types) appear before all methods, getters, setters, and operators (ignoring constructors), grouped by scope in the following order and sorted alphabetically within each scope:

1. Public `static const` fields
2. Private `static const` fields
3. Public `static` fields
4. Private `static` fields
5. Public instance fields
6. Private instance fields

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

Fields, constructors, and operators are ignored. Includes an automated quick fix (`Sort functions by scope`).

### `sort_functions_alphabetically`

Ensures functions, getters, and setters within a type body are sorted alphabetically (lexicographically) within each scope (e.g., all public static getters alphabetically, all public static setters alphabetically, all public static functions alphabetically, etc.).

Fields, constructors, and operators are ignored. Includes an automated quick fix (`Sort functions alphabetically`).

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
