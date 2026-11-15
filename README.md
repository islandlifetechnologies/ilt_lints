# ilt_lints Workspace

A Dart monorepo containing custom analyzer lint rules, automated quick-fix CLI tooling, and a static Jaspr documentation site builder for Island Life Technologies projects.

## Packages

| Package | Description |
| :--- | :--- |
| [`ilt_lints`](packages/ilt_lints) | Custom Dart & Flutter lint rules and automated quick fixes built on `analyzer` and `analysis_server_plugin`, along with the canonical [`assets/lints.yaml`](packages/ilt_lints/assets/lints.yaml) specification. |
| [`jaspr_lint_builder`](packages/jaspr_lint_builder) | Static documentation website generator (powered by [Jaspr](https://pub.dev/packages/jaspr)) and JSON Schema validator (`json_schema` + `yaon`) that validates `lints.yaml` against [`assets/lint_schema.yaml`](packages/jaspr_lint_builder/assets/lint_schema.yaml) and builds HTML, CSS, and JS documentation pages. |
| [`quick_fix`](packages/quick_fix) | Reusable library that allows custom lint packages to wrap their `AnalysisRule` and `ResolvedCorrectionProducer` implementations into a command-line quick-fix runner (similar to `dart fix --apply`). |

## Repository Structure

```text
.
├── .github/workflows/
│   ├── gh_pages.yaml           # Builds and publishes the lint documentation site to the gh_pages orphan branch
│   ├── publish.yaml            # Detects changed packages via gh_tools, validates, tags, and publishes them
│   └── validate.yaml           # Detects changed packages via gh_tools and validates them on PRs
├── .pre-commit-config.yaml     # Monorepo pre-commit hooks powered by gh_tools
├── analysis_options.yaml       # Root workspace analyzer configuration
├── pubspec.yaml                # Dart Pub Workspace definition
└── packages/
    ├── ilt_lints/              # Custom lint rules, quick fixes, and assets/lints.yaml
    ├── jaspr_lint_builder/     # Static site builder, schema validator, and example server
    └── quick_fix/              # CLI quick-fix runner library for custom lint plugins
```

## Getting Started

### Resolve Workspace Dependencies

From the repository root:

```sh
dart pub get
```

### Validating `lints.yaml` and Building the Documentation Site

Validate `packages/ilt_lints/assets/lints.yaml` against `packages/jaspr_lint_builder/assets/lint_schema.yaml`:

```sh
dart pub run jaspr_lint_builder:validate \
  --input packages/ilt_lints/assets/lints.yaml
```

Generate the static documentation website:

```sh
dart pub run jaspr_lint_builder:build \
  --favicon packages/ilt_lints/assets/favicon.png \
  --input packages/ilt_lints/assets/lints.yaml \
  --output build/web
```

### Running Automated Quick Fixes

Run all enabled `ilt_lints` quick fixes across a project:

```sh
dart pub run ilt_lints:fix
```
