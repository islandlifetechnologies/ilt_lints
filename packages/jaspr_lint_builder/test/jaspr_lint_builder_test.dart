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
      expect(doc.lints, hasLength(10));
      expect(
        doc.lints.map((l) => l.name),
        containsAll([
          'export_library',
          'prefer_const_constructors',
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
        expect(rule.doStatement, isNotEmpty);
        expect(rule.bad, isNotEmpty);
        expect(rule.good, isNotEmpty);
        expect(rule.enable, isNotEmpty);
        expect(rule.quickFix, isTrue);
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
        expect(result.rules, hasLength(10));
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
        expect(indexHtml, contains('Linter rules'));
        expect(indexHtml, contains('All linter rules'));
        expect(indexHtml, contains('styles.css'));
        expect(indexHtml, contains('main.client.dart.js'));

        for (final rule in result.rules) {
          expect(indexHtml, contains(rule.name));

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
          expect(ruleHtml, contains('Fix available'));
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
        expect(outBuffer.toString(), contains('10 lint rules (ILT Lints)'));
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
  });
}
