import 'dart:convert' show utf8;
import 'dart:io' as io show stderr, stdout;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:jaspr/dom.dart' show link, script;
import 'package:jaspr/server.dart';
import 'package:path/path.dart' as p;

import 'assets/site_script.dart';
import 'assets/site_styles.dart';
import 'components/lint_detail_page.dart';
import 'components/lint_index_page.dart';
import 'components/markdown_content.dart';
import 'favicon_generator.dart';
import 'lint_schema_validator.dart';
import 'models/custom_lint_config.dart';

/// CLI runner for `jaspr_lint_builder` that accepts a `lints.yaml` file,
/// validates it against `assets/lint_schema.yaml`, and generates a static Jaspr
/// documentation website (HTML, CSS, and JS).
Future<int> runJasprLintBuilderCli(
  List<String> args, {
  StringSink? err,
  FileSystem fs = const LocalFileSystem(),
  StringSink? out,
  String? schemaFilePath,
}) async {
  final parser = ArgParser()
    ..addOption(
      'favicon',
      abbr: 'f',
      help: 'Optional path to a PNG image file used to generate site favicons.',
    )
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: '../ilt_lints/assets/lints.yaml',
      help: 'Path to the input lints.yaml file matching lint_schema.yaml.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'build/web',
      help: 'Output directory for generated HTML, CSS, and JS files.',
    )
    ..addOption(
      'schema',
      abbr: 's',
      help: 'Optional path to the lint_schema.yaml file.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Display usage information.',
      negatable: false,
    );

  final stdoutSink = out ?? io.stdout;
  final stderrSink = err ?? io.stderr;

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (error) {
    stderrSink.writeln('Error: ${error.message}');
    stderrSink.writeln(parser.usage);
    return 64;
  }

  if (parsed['help'] == true) {
    stdoutSink.writeln(
      'Generates a static Dart linter documentation site using Jaspr.',
    );
    stdoutSink.writeln();
    stdoutSink.writeln(parser.usage);
    return 0;
  }

  final explicitInput = parsed.wasParsed('input') || parsed.rest.isNotEmpty;
  final faviconPath = parsed['favicon'] as String?;
  final rawInput = parsed.wasParsed('input')
      ? parsed['input'] as String
      : (parsed.rest.isNotEmpty
            ? parsed.rest.first
            : parsed['input'] as String);
  final outputDir = parsed['output'] as String;
  final resolvedSchemaPath = (parsed['schema'] as String?) ?? schemaFilePath;

  final resolvedInput = resolveLintInputFilePath(
    fs,
    rawInput,
    allowFallbacks: !explicitInput,
  );
  if (resolvedInput == null) {
    stderrSink.writeln('Input YAML file does not exist: $rawInput');
    return 66;
  }

  try {
    final builder = JasprLintSiteBuilder(
      faviconFilePath: faviconPath,
      fs: fs,
      schemaFilePath: resolvedSchemaPath,
    );
    final result = await builder.buildFromYamlFile(
      outputDirectoryPath: outputDir,
      yamlFilePath: resolvedInput,
    );
    stdoutSink.writeln(
      'Generated ${result.generatedFiles.length} files for '
      '${result.rules.length} lint rules (${result.title}) '
      'in ${result.outputDirectoryPath}.',
    );
    return 0;
  } on FormatException catch (error) {
    stderrSink.writeln('Invalid lint YAML specification: ${error.message}');
    return 65;
  }
}

/// Builds a static linter documentation website (HTML, CSS, and JS) using the
/// Jaspr framework from a YAML specification conforming to `lint_schema.yaml`.
class const JasprLintSiteBuilder({
  final String? faviconFilePath,
  final FileSystem fs = const LocalFileSystem(),
  final String? schemaFilePath,
}) {
  static var _jasprInitialized = false;

  /// Generates the static website into [outputDirectoryPath] from a parsed
  /// [CustomLintsDocument].
  Future<LintSiteBuildResult> buildFromDocument({
    required CustomLintsDocument document,
    String? faviconFilePath,
    required String outputDirectoryPath,
  }) async {
    _ensureJasprInitialized();

    final outputDir = fs.directory(outputDirectoryPath);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final generatedFiles = <String>[];
    final packageName = document.packageName ?? 'ilt_lints';
    final rules = document.lints;
    final siteDescription = document.description;
    final siteTitle = document.title;
    final version = document.version ?? '^2.0.0';
    final resolvedFaviconPath = faviconFilePath ?? this.faviconFilePath;
    final hasFavicons = resolvedFaviconPath != null;

    if (resolvedFaviconPath != null) {
      final faviconFiles = FaviconGenerator(fs: fs).generateFavicons(
        faviconFilePath: resolvedFaviconPath,
        outputDirectoryPath: outputDir.path,
      );
      generatedFiles.addAll(faviconFiles);
    }

    Future<void> writeSiteFile(String relativePath, String content) async {
      final fullPath = p.join(outputDir.path, relativePath);
      final file = fs.file(fullPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(content);
      generatedFiles.add(fullPath);
    }

    final jsContent = buildSiteScript();
    await writeSiteFile('styles.css', buildSiteStylesheet());
    await writeSiteFile('main.js', jsContent);
    await writeSiteFile('main.client.dart.js', jsContent);

    final rootIndexHtml = await renderIndexPageHtml(
      includeFavicons: hasFavicons,
      package: packageName,
      rootPrefix: '',
      rules: rules,
      siteDescription: siteDescription,
      siteTitle: siteTitle,
      version: version,
    );
    await writeSiteFile('index.html', rootIndexHtml);

    final subIndexHtml = await renderIndexPageHtml(
      includeFavicons: hasFavicons,
      package: packageName,
      rootPrefix: '../',
      rules: rules,
      siteDescription: siteDescription,
      siteTitle: siteTitle,
      version: version,
    );
    await writeSiteFile(p.join('linter-rules', 'index.html'), subIndexHtml);

    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      final previousRule = i > 0 ? rules[i - 1] : null;
      final nextRule = i + 1 < rules.length ? rules[i + 1] : null;

      final detailHtml = await renderRuleDetailPageHtml(
        includeFavicons: hasFavicons,
        nextRule: nextRule,
        previousRule: previousRule,
        rootPrefix: '../',
        rule: rule,
        rules: rules,
        siteTitle: siteTitle,
      );
      await writeSiteFile(
        p.join('linter-rules', '${rule.name}.html'),
        detailHtml,
      );

      final nestedDetailHtml = await renderRuleDetailPageHtml(
        includeFavicons: hasFavicons,
        nextRule: nextRule,
        previousRule: previousRule,
        rootPrefix: '../../',
        rule: rule,
        rules: rules,
        siteTitle: siteTitle,
      );
      await writeSiteFile(
        p.join('linter-rules', rule.name, 'index.html'),
        nestedDetailHtml,
      );
    }

    return LintSiteBuildResult(
      description: siteDescription,
      generatedFiles: List<String>.unmodifiable(generatedFiles),
      outputDirectoryPath: outputDir.path,
      rules: rules,
      title: siteTitle,
    );
  }

  /// Reads [yamlFilePath], validates it against the custom lint schema, and
  /// generates the website into [outputDirectoryPath].
  Future<LintSiteBuildResult> buildFromYamlFile({
    String? faviconFilePath,
    required String outputDirectoryPath,
    required String yamlFilePath,
  }) {
    final file = fs.file(yamlFilePath);
    if (!file.existsSync()) {
      throw FormatException('YAML file does not exist: $yamlFilePath');
    }
    final yamlContent = file.readAsStringSync();
    return buildFromYamlString(
      faviconFilePath: faviconFilePath,
      outputDirectoryPath: outputDirectoryPath,
      yamlContent: yamlContent,
    );
  }

  /// Parses [yamlContent], validates it against the custom lint schema, and
  /// generates the website into [outputDirectoryPath].
  Future<LintSiteBuildResult> buildFromYamlString({
    String? faviconFilePath,
    required String outputDirectoryPath,
    required String yamlContent,
  }) {
    final document = CustomLintsDocument.fromYamlString(
      yamlContent,
      fs: fs,
      schemaFilePath: schemaFilePath,
    );
    return buildFromDocument(
      document: document,
      faviconFilePath: faviconFilePath,
      outputDirectoryPath: outputDirectoryPath,
    );
  }

  /// Renders the main Linter Rules index page into an HTML string using Jaspr.
  Future<String> renderIndexPageHtml({
    bool includeFavicons = false,
    String package = 'ilt_lints',
    String rootPrefix = '',
    required List<CustomLintRule> rules,
    String? siteDescription,
    required String siteTitle,
    String version = '^2.0.0',
  }) async {
    _ensureJasprInitialized();
    final metaDescription =
        (siteDescription != null && siteDescription.trim().isNotEmpty)
        ? MarkdownContent.stripMarkdown(siteDescription.trim())
        : 'All custom Dart linter rules and quick fixes for $siteTitle.';
    final document = _buildDocumentShell(
      body: LintIndexPage(
        package: package,
        rootPrefix: rootPrefix,
        rules: rules,
        siteDescription: siteDescription,
        siteTitle: siteTitle,
        version: version,
      ),
      description: metaDescription,
      includeFavicons: includeFavicons,
      rootPrefix: rootPrefix,
      title: 'Linter rules | $siteTitle',
    );
    final rendered = await renderComponent(document);
    return utf8.decode(rendered.body);
  }

  /// Renders an individual Linter Rule detail page into an HTML string using
  /// Jaspr.
  Future<String> renderRuleDetailPageHtml({
    bool includeFavicons = false,
    CustomLintRule? nextRule,
    CustomLintRule? previousRule,
    String rootPrefix = '../',
    required CustomLintRule rule,
    required List<CustomLintRule> rules,
    required String siteTitle,
  }) async {
    _ensureJasprInitialized();
    final summary =
        rule.doStatement ??
        rule.avoidStatement ??
        MarkdownContent.stripMarkdown(rule.description);
    final document = _buildDocumentShell(
      body: LintDetailPage(
        nextRule: nextRule,
        previousRule: previousRule,
        rootPrefix: rootPrefix,
        rule: rule,
        rules: rules,
        siteTitle: siteTitle,
      ),
      description: '${rule.name}: $summary',
      includeFavicons: includeFavicons,
      rootPrefix: rootPrefix,
      title: '${rule.name} | Linter rules | $siteTitle',
    );
    final rendered = await renderComponent(document);
    return utf8.decode(rendered.body);
  }

  Document _buildDocumentShell({
    required Component body,
    required String description,
    required bool includeFavicons,
    required String rootPrefix,
    required String title,
  }) => Document(
    body: body,
    head: [
      if (includeFavicons) ...[
        link(
          href: '${rootPrefix}favicon.ico',
          rel: 'icon',
          type: 'image/x-icon',
        ),
        link(
          attributes: const {'sizes': '16x16'},
          href: '${rootPrefix}favicon-16x16.png',
          rel: 'icon',
          type: 'image/png',
        ),
        link(
          attributes: const {'sizes': '32x32'},
          href: '${rootPrefix}favicon-32x32.png',
          rel: 'icon',
          type: 'image/png',
        ),
        link(
          attributes: const {'sizes': '48x48'},
          href: '${rootPrefix}favicon-48x48.png',
          rel: 'icon',
          type: 'image/png',
        ),
        link(
          attributes: const {'sizes': '180x180'},
          href: '${rootPrefix}apple-touch-icon.png',
          rel: 'apple-touch-icon',
        ),
        link(
          attributes: const {'sizes': '192x192'},
          href: '${rootPrefix}favicon-192x192.png',
          rel: 'icon',
          type: 'image/png',
        ),
        link(
          attributes: const {'sizes': '512x512'},
          href: '${rootPrefix}favicon-512x512.png',
          rel: 'icon',
          type: 'image/png',
        ),
      ],
      link(href: '${rootPrefix}styles.css', rel: 'stylesheet'),
      script(defer: true, src: '${rootPrefix}main.client.dart.js'),
    ],
    lang: 'en',
    meta: {'description': description},
    styles: buildJasprStyleRules(),
    title: title,
  );

  void _ensureJasprInitialized() {
    if (!_jasprInitialized) {
      Jaspr.initializeApp();
      _jasprInitialized = true;
    }
  }
}
