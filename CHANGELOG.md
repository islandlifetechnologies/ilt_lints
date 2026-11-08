## 2.0.0

- Pulled last beta version into release.

## 2.0.0-beta6

- Added `prefer_const_constructors` lint rule to encourage marking constructors `const` when a class can be `const` without other changes.
- Added `prefer_primary_constructors` lint rule to encourage the use of Primary Constructors.
- Added `use_clock` lint rule to encourage using the `clock` package instead of `DateTime.now()`.
- Added `use_file_system` lint rule to encourage using the `file_system` package instead of `dart:io`.

## 2.0.0-beta5

- Added `valid_json_serializable` to validate if a file has @JsonSerializable annotation, proper fromJson/toJson factory/methods, with quick fix.

## 2.0.0-beta4

- Updated to have `export_library` take a list for `include` / `exclude` rather than a single string.

## 2.0.0-beta3

- Rolled version and retriggered build due to GH Action issue.

## 2.0.0-beta2

- Added custom `export_library` rule but does not utilize the rule in the default rule set.

## 2.0.0-beta1

- Added custom `sort_fields`, `sort_functions_by_scope`, `sort_functions_alphabetically`, and `sort_named_parameters` lint rules and included them in the default list.

## 1.0.1

- Added `unnecessary_primary_constructor_body` to default rule list.

## 1.0.0+1

- Initial release
