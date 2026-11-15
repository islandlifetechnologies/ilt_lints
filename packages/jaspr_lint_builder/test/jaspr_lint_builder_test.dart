import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:image/image.dart' as img;
import 'package:jaspr_lint_builder/jaspr_lint_builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _findIltFaviconPngPath() {
  final candidates = [
    p.join('..', 'ilt_lints', 'assets', 'favicon.png'),
    p.join('packages', 'ilt_lints', 'assets', 'favicon.png'),
  ];
  for (final candidate in candidates) {
    if (io.File(candidate).existsSync()) {
      return candidate;
    }
  }
  throw StateError('Could not locate packages/ilt_lints/assets/favicon.png');
}

String _findIltLintsYamlPath() {
  final candidates = [
    p.join('..', 'ilt_lints', 'assets', 'lints.yaml'),
    p.join('packages', 'ilt_lints', 'assets', 'lints.yaml'),
  ];
  for (final candidate in candidates) {
    if (io.File(candidate).existsSync()) {
      return candidate;
    }
  }
  throw StateError('Could not locate packages/ilt_lints/assets/lints.yaml');
}

void main() {
  group('LintSchemaValidator', () {
    test('validates ilt_lints/assets/lints.yaml against lint_schema.yaml', () {
      final path = _findIltLintsYamlPath();
      final results = validateLintYamlFile(path);

      expect(results.isValid, isTrue, reason: results.errors.join('\n'));
      expect(results.errors, isEmpty);
    });

    test('fails validation when required top-level title is missing', () {
      const invalidYaml = '''
lints: []
''';
      final results = validateLintYamlString(invalidYaml);

      expect(results.isValid, isFalse);
      expect(results.errors, isNotEmpty);
    });

    test('fails validation when required lint properties are missing', () {
      const invalidYaml = '''
title: Test Lints
lints:
  - name: incomplete_rule
    description: Missing do, bad, good, and enable.
''';
      final results = validateLintYamlString(invalidYaml);

      expect(results.isValid, isFalse);
      expect(results.errors, isNotEmpty);
      expect(
        () => const LintSchemaValidator().assertValidYamlString(invalidYaml),
        throwsFormatException,
      );
    });

    test('fails validation when unexpected top-level property is present', () {
      const invalidYaml = '''
title: Test Lints
lints: []
unexpected_root_key: true
''';
      final results = validateLintYamlString(invalidYaml);

      expect(results.isValid, isFalse);
      expect(results.errors, isNotEmpty);
    });

    test('fails validation when property types do not match schema', () {
      const invalidYaml = '''
title: Test Lints
lints:
  - name: invalid_types_rule
    description: Valid description.
    do: Do something.
    bad: "not_a_list"
    good:
      - "log('good');"
    quick_fix: "not_a_bool"
    enable: |
      linter:
        rules:
          - invalid_types_rule
''';
      final results = validateLintYamlString(invalidYaml);

      expect(results.isValid, isFalse);
      expect(results.errors, isNotEmpty);
    });
  });

  group('validate CLI (runJasprLintValidateCli)', () {
    test('returns 0 for valid lints.yaml without building site', () async {
      final memoryFs = MemoryFileSystem();
      final yamlContent = io.File(_findIltLintsYamlPath()).readAsStringSync();
      memoryFs.file('/workspace/lints.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(yamlContent);

      final outBuffer = StringBuffer();
      final errBuffer = StringBuffer();
      final code = await runJasprLintValidateCli(
        ['--input', '/workspace/lints.yaml'],
        err: errBuffer,
        fs: memoryFs,
        out: outBuffer,
      );

      expect(code, 0);
      expect(errBuffer.toString(), isEmpty);
      expect(outBuffer.toString(), contains('Validated /workspace/lints.yaml'));
      expect(memoryFs.directory('/workspace/build').existsSync(), isFalse);
    });

    test('returns non-zero exit code when schema validation fails', () async {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('/workspace/invalid_lints.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
title: Invalid Lints
lints:
  - name: broken_rule
    description: Missing required fields.
''');
      final outBuffer = StringBuffer();
      final errBuffer = StringBuffer();
      final code = await runJasprLintValidateCli(
        ['--input', '/workspace/invalid_lints.yaml'],
        err: errBuffer,
        fs: memoryFs,
        out: outBuffer,
      );

      expect(code, isNonZero);
      expect(errBuffer.toString(), contains('Invalid lint YAML specification'));
    });

    test('returns non-zero exit code when input file does not exist', () async {
      final memoryFs = MemoryFileSystem();
      final outBuffer = StringBuffer();
      final errBuffer = StringBuffer();
      final code = await runJasprLintValidateCli(
        ['--input', '/workspace/missing.yaml'],
        err: errBuffer,
        fs: memoryFs,
        out: outBuffer,
      );

      expect(code, isNonZero);
      expect(errBuffer.toString(), contains('Input YAML file does not exist'));
    });
  });

  group('CustomLintsDocument', () {
    test('parses ilt_lints/assets/lints.yaml successfully', () {
      final yamlContent = io.File(_findIltLintsYamlPath()).readAsStringSync();
      final doc = CustomLintsDocument.fromYamlString(yamlContent);

      expect(doc.title, 'ILT Lints');
      expect(doc.description, isNotNull);
      expect(doc.description, contains('Custom lint rules for use in ILT'));
      expect(doc.lints, hasLength(12));
      expect(
        doc.lints.map((l) => l.name),
        containsAll([
          'avoid_large_ccn',
          'export_library',
          'prefer_const_constructors',
          'prefer_named_parameters',
          'prefer_primary_constructors',
          'sort_fields',
          'sort_functions_alphabetically',
          'sort_functions_by_scope',
          'sort_named_parameters',
          'use_clock',
          'use_file_system',
          'valid_json_serializable',
        ]),
      );
      for (final rule in doc.lints) {
        expect(rule.description, isNotEmpty);
        expect(rule.doStatement != null || rule.avoidStatement != null, isTrue);
        expect(rule.bad, isNotEmpty);
        expect(rule.good, isNotEmpty);
        expect(rule.enable, isNotEmpty);
        expect(rule.quickFix, rule.name != 'avoid_large_ccn');
        expect(rule.tags, isNotEmpty);
      }
    });

    test('throws FormatException on missing required property', () {
      const invalidYaml = '''
title: Test Lints
lints:
  - name: incomplete_rule
    description: Missing do, bad, good, and enable.
''';
      expect(
        () => CustomLintsDocument.fromYamlString(invalidYaml),
        throwsFormatException,
      );
    });

    test('throws FormatException on unexpected property', () {
      const invalidYaml = '''
title: Test Lints
lints:
  - name: extra_prop_rule
    description: Some description.
    do: Do something.
    bad:
      - "print('bad');"
    good:
      - "log('good');"
    enable: |
      linter:
        rules:
          - extra_prop_rule
    unknown_field: true
''';
      expect(
        () => CustomLintsDocument.fromYamlString(invalidYaml),
        throwsFormatException,
      );
    });
  });

  group('FaviconGenerator', () {
    test('resizes ilt_lints/assets/favicon.png into favicon assets', () {
      final memoryFs = MemoryFileSystem();
      final faviconBytes = io.File(_findIltFaviconPngPath()).readAsBytesSync();
      memoryFs.file('/input/favicon.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(faviconBytes);

      final generator = FaviconGenerator(fs: memoryFs);
      final generated = generator.generateFavicons(
        faviconFilePath: '/input/favicon.png',
        outputDirectoryPath: '/output/web',
      );

      expect(generated, hasLength(7));
      expect(memoryFs.file('/output/web/favicon.ico').existsSync(), isTrue);

      final expectedDimensions = <String, int>{
        'apple-touch-icon.png': 180,
        'favicon-16x16.png': 16,
        'favicon-32x32.png': 32,
        'favicon-48x48.png': 48,
        'favicon-192x192.png': 192,
        'favicon-512x512.png': 512,
      };
      for (final entry in expectedDimensions.entries) {
        final file = memoryFs.file('/output/web/${entry.key}');
        expect(file.existsSync(), isTrue);
        final decoded = img.decodePng(
          Uint8List.fromList(file.readAsBytesSync()),
        );
        expect(decoded, isNotNull);
        expect(decoded!.width, entry.value);
        expect(decoded.height, entry.value);
      }
    });

    test('rejects non-PNG file extension', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('/input/favicon.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);

      final generator = FaviconGenerator(fs: memoryFs);
      expect(
        () => generator.generateFavicons(
          faviconFilePath: '/input/favicon.jpg',
          outputDirectoryPath: '/output/web',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-PNG file data even with .png extension', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('/input/fake.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('not a valid png');

      final generator = FaviconGenerator(fs: memoryFs);
      expect(
        () => generator.generateFavicons(
          faviconFilePath: '/input/fake.png',
          outputDirectoryPath: '/output/web',
        ),
        throwsFormatException,
      );
    });
  });

  group('JasprLintSiteBuilder', () {
    test(
      'generates HTML, CSS, and JS files for ilt_lints/assets/lints.yaml',
      () async {
        final memoryFs = MemoryFileSystem();
        final yamlContent = io.File(_findIltLintsYamlPath()).readAsStringSync();
        memoryFs.file('/input/lints.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync(yamlContent);

        final builder = JasprLintSiteBuilder(fs: memoryFs);
        final result = await builder.buildFromYamlFile(
          outputDirectoryPath: '/output/site',
          yamlFilePath: '/input/lints.yaml',
        );

        expect(result.title, 'ILT Lints');
        expect(result.rules, hasLength(12));
        expect(memoryFs.file('/output/site/styles.css').existsSync(), isTrue);
        expect(memoryFs.file('/output/site/main.js').existsSync(), isTrue);
        expect(
          memoryFs.file('/output/site/main.client.dart.js').existsSync(),
          isTrue,
        );
        expect(memoryFs.file('/output/site/index.html').existsSync(), isTrue);
        expect(
          memoryFs.file('/output/site/linter-rules/index.html').existsSync(),
          isTrue,
        );

        final mainJs = memoryFs.file('/output/site/main.js').readAsStringSync();
        expect(mainJs, contains('tok-key'));
        expect(mainJs, contains('tok-str'));
        expect(mainJs, contains('tok-obj'));
        expect(mainJs, contains('tok-cmt-code'));

        final stylesCss = memoryFs
            .file('/output/site/styles.css')
            .readAsStringSync();
        expect(stylesCss, contains('.tok-key'));
        expect(stylesCss, contains('.tok-obj'));
        expect(stylesCss, contains('.tok-str'));
        expect(stylesCss, contains('.tok-cmt-code'));

        final indexHtml = memoryFs
            .file('/output/site/index.html')
            .readAsStringSync();
        expect(indexHtml, contains('ILT Lints'));
        expect(indexHtml, contains('Custom lint rules for use in ILT'));
        expect(indexHtml, contains('include: package:ilt_lints/lints.yaml'));
        expect(indexHtml, contains('markdown-code-card'));
        expect(indexHtml, contains('Linter rules'));
        expect(indexHtml, contains('All linter rules'));
        expect(indexHtml, contains('styles.css'));
        expect(indexHtml, contains('main.client.dart.js'));
        expect(indexHtml, contains('data-filter="tag:performance"'));
        expect(indexHtml, contains('data-filter="tag:style"'));
        expect(indexHtml, contains('data-filter="tag:testability"'));
        expect(indexHtml, contains('data-filter="tag:utility"'));

        for (final rule in result.rules) {
          expect(indexHtml, contains(rule.name));
          for (final tag in rule.tags) {
            expect(indexHtml, contains('#$tag'));
          }

          final rulePageFile = memoryFs.file(
            '/output/site/linter-rules/${rule.name}.html',
          );
          expect(rulePageFile.existsSync(), isTrue);

          final nestedPageFile = memoryFs.file(
            '/output/site/linter-rules/${rule.name}/index.html',
          );
          expect(nestedPageFile.existsSync(), isTrue);

          final ruleHtml = rulePageFile.readAsStringSync();
          expect(ruleHtml, contains(rule.name));
          expect(ruleHtml, contains('ILT Lints'));
          expect(ruleHtml, contains('Details'));
          expect(ruleHtml, contains('Examples'));
          expect(ruleHtml, contains('BAD:'));
          expect(ruleHtml, contains('GOOD:'));
          expect(ruleHtml, contains('How to enable'));
          expect(ruleHtml, contains('analysis_options.yaml'));
          expect(
            ruleHtml,
            contains(rule.quickFix ? 'Fix available' : 'No quick fix'),
          );
          for (final tag in rule.tags) {
            expect(ruleHtml, contains('#$tag'));
          }
        }
      },
    );

    test(
      'CLI runner generates website and favicons when --favicon is passed',
      () async {
        final memoryFs = MemoryFileSystem();
        final yamlContent = io.File(_findIltLintsYamlPath()).readAsStringSync();
        final faviconBytes = io.File(_findIltFaviconPngPath())
            .readAsBytesSync();
        memoryFs.file('/workspace/lints.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync(yamlContent);
        memoryFs.file('/workspace/favicon.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(faviconBytes);

        final outBuffer = StringBuffer();
        final errBuffer = StringBuffer();
        final code = await runJasprLintBuilderCli(
          [
            '--favicon',
            '/workspace/favicon.png',
            '--input',
            '/workspace/lints.yaml',
            '--output',
            '/workspace/build/web',
          ],
          err: errBuffer,
          fs: memoryFs,
          out: outBuffer,
        );

        expect(code, 0);
        expect(errBuffer.toString(), isEmpty);
        expect(outBuffer.toString(), contains('12 lint rules (ILT Lints)'));
        expect(
          memoryFs.file('/workspace/build/web/index.html').existsSync(),
          isTrue,
        );
        expect(
          memoryFs.file('/workspace/build/web/favicon.ico').existsSync(),
          isTrue,
        );
        expect(
          memoryFs.file('/workspace/build/web/favicon-32x32.png').existsSync(),
          isTrue,
        );
        expect(
          memoryFs
              .file('/workspace/build/web/apple-touch-icon.png')
              .existsSync(),
          isTrue,
        );

        final indexHtml = memoryFs
            .file('/workspace/build/web/index.html')
            .readAsStringSync();
        expect(indexHtml, contains('favicon.ico'));
        expect(indexHtml, contains('favicon-32x32.png'));
        expect(indexHtml, contains('apple-touch-icon.png'));
      },
    );

    test(
      'renders markdown links and fenced code blocks in descriptions',
      () async {
        final memoryFs = MemoryFileSystem();
        const markdownYaml = '''
title: Markdown Lints
description: |
  See the [ILT Lints repository](https://github.com/islandlifetechnologies/ilt_lints)
  for **full** documentation and `analysis_options.yaml` setup:

  ```yaml
  include: package:ilt_lints/lints.yaml
  ```
package: ilt_lints
version: ^2.0.0
lints:
  - name: sample_markdown_rule
    tags:
      - style
    description: |
      Read the [Dart guide](https://dart.dev/guides) before using `sample_markdown_rule`.

      ```dart
      void example() {}
      ```
    do: Follow the [style guide](https://dart.dev).
    bad:
      - "void bad() {}"
    good:
      - "void good() {}"
    quick_fix: true
    enable: |
      plugins:
        ilt_lints:
          diagnostics:
            sample_markdown_rule: true
''';

        final builder = JasprLintSiteBuilder(fs: memoryFs);
        await builder.buildFromYamlString(
          outputDirectoryPath: '/output/md_site',
          yamlContent: markdownYaml,
        );

        final indexHtml = memoryFs
            .file('/output/md_site/index.html')
            .readAsStringSync();
        expect(
          indexHtml,
          contains(
            'href="https://github.com/islandlifetechnologies/ilt_lints"',
          ),
        );
        expect(indexHtml, contains('ILT Lints repository'));
        expect(indexHtml, contains('<strong>full</strong>'));
        expect(indexHtml, contains('include: package:ilt_lints/lints.yaml'));
        expect(indexHtml, contains('class="language-yaml"'));
        expect(indexHtml, contains('markdown-code-card'));

        final detailHtml = memoryFs
            .file('/output/md_site/linter-rules/sample_markdown_rule.html')
            .readAsStringSync();
        expect(detailHtml, contains('href="https://dart.dev/guides"'));
        expect(detailHtml, contains('Dart guide'));
        expect(detailHtml, contains('void example() {}'));
        expect(detailHtml, contains('class="language-dart"'));
      },
    );

    test(
      'renders avoid guidelines and omits do section when do is not passed in',
      () async {
        final memoryFs = MemoryFileSystem();
        const avoidYaml = '''
title: Avoid Lints
lints:
  - name: avoid_only_rule
    description: Rule with only avoid and no do.
    avoid: Avoid calling `DateTime.now()` directly.
    bad:
      - "DateTime.now();"
    good:
      - "clock.now();"
    enable: |
      linter:
        rules:
          - avoid_only_rule
  - name: neither_do_nor_avoid_rule
    description: Rule with neither do nor avoid.
    bad:
      - "bad();"
    good:
      - "good();"
    enable: |
      linter:
        rules:
          - neither_do_nor_avoid_rule
''';

        final builder = JasprLintSiteBuilder(fs: memoryFs);
        await builder.buildFromYamlString(
          outputDirectoryPath: '/output/avoid_site',
          yamlContent: avoidYaml,
        );

        final indexHtml = memoryFs
            .file('/output/avoid_site/index.html')
            .readAsStringSync();
        expect(indexHtml, contains('AVOID '));
        expect(indexHtml, contains('calling'));
        expect(indexHtml, isNot(contains('rule-card-do')));

        final avoidDetailHtml = memoryFs
            .file('/output/avoid_site/linter-rules/avoid_only_rule.html')
            .readAsStringSync();
        expect(avoidDetailHtml, contains('avoid-guideline-paragraph'));
        expect(avoidDetailHtml, contains('AVOID '));
        expect(avoidDetailHtml, isNot(contains('do-guideline-paragraph')));

        final neitherDetailHtml = memoryFs
            .file(
              '/output/avoid_site/linter-rules/neither_do_nor_avoid_rule.html',
            )
            .readAsStringSync();
        expect(neitherDetailHtml, isNot(contains('avoid-guideline-paragraph')));
        expect(neitherDetailHtml, isNot(contains('do-guideline-paragraph')));
      },
    );
  });
}
