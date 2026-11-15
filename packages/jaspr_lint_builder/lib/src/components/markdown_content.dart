import 'package:jaspr/dom.dart' show RawText;
import 'package:jaspr/jaspr.dart';

/// Renders a Markdown string into Jaspr [Component] elements, supporting
/// paragraphs, headings, unordered/ordered lists, blockquotes, horizontal
/// rules, fenced code blocks (` ``` ` / `~~~`) with language formatting and
/// copy buttons, inline code spans, links (`[text](url)` and `<https://...>`),
/// bold, italic, and strikethrough formatting.
class const MarkdownContent({
  final String? classes,
  required final String content,
  super.key,
}) extends StatelessComponent {
  static const _copyIconSvg =
      '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round" aria-hidden="true">'
      '<rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>'
      '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>'
      '</svg>';

  /// Parses inline Markdown formatting (code spans, links, bold, italic,
  /// strikethrough) into a list of Jaspr [Component] nodes.
  static List<Component> parseInline(String text) => _parseInlineNodes(text);

  /// Strips Markdown syntax (fenced code blocks, links, inline code, emphasis)
  /// into a single-line plain text summary suitable for HTML meta descriptions
  /// or search indexing.
  static String stripMarkdown(String markdown) {
    var result = markdown.replaceAll(
      RegExp(r'(```+|~~~+)[^\n]*\n[\s\S]*?\1', multiLine: true),
      ' ',
    );
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAll('`', '');
    result = result.replaceAll(RegExp(r'(\*\*|__|~~)'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  static Component _buildCodeFenceBlock({
    required String code,
    required String language,
  }) {
    final normalizedLang = language.trim().toLowerCase();
    final isYaml = normalizedLang == 'yaml' || normalizedLang == 'yml';
    final isDart = normalizedLang == 'dart';
    final isJson = normalizedLang == 'json';
    final isShell =
        normalizedLang == 'sh' ||
        normalizedLang == 'bash' ||
        normalizedLang == 'shell' ||
        normalizedLang == 'zsh';

    final String languageClass;
    final String headerTitle;
    final String headerClass;
    if (isYaml) {
      languageClass = 'language-yaml';
      headerTitle = 'YAML';
      headerClass = 'code-block-header yaml-header';
    } else if (isDart) {
      languageClass = 'language-dart';
      headerTitle = 'Dart';
      headerClass = 'code-block-header dart-header';
    } else if (isJson) {
      languageClass = 'language-json';
      headerTitle = 'JSON';
      headerClass = 'code-block-header';
    } else if (isShell) {
      languageClass = 'language-sh';
      headerTitle = 'Shell';
      headerClass = 'code-block-header';
    } else if (normalizedLang.isNotEmpty) {
      languageClass = 'language-$normalizedLang';
      headerTitle = normalizedLang.toUpperCase();
      headerClass = 'code-block-header';
    } else {
      languageClass = 'language-text';
      headerTitle = 'Code';
      headerClass = 'code-block-header';
    }

    return Component.element(
      children: [
        Component.element(
          children: [
            Component.element(
              children: [Component.text(headerTitle)],
              classes: 'code-block-title',
              tag: 'span',
            ),
            Component.element(
              attributes: {
                'aria-label': 'Copy $headerTitle code',
                'type': 'button',
              },
              children: const [RawText(_copyIconSvg), Component.text(' Copy')],
              classes: 'copy-code-btn',
              tag: 'button',
            ),
          ],
          classes: headerClass,
          tag: 'div',
        ),
        Component.element(
          children: [
            Component.element(
              children: [Component.text(code)],
              classes: languageClass,
              tag: 'code',
            ),
          ],
          classes: isYaml ? 'code-block yaml-code' : 'code-block',
          tag: 'pre',
        ),
      ],
      classes: 'code-card markdown-code-card',
      tag: 'div',
    );
  }

  static bool _isAlphaNumeric(int codeUnit) =>
      (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);

  static bool _isBlockStart(String trimmedLine) {
    if (trimmedLine.isEmpty) {
      return true;
    }
    if (RegExp(r'^(`{3,}|~{3,})').hasMatch(trimmedLine)) {
      return true;
    }
    if (RegExp(r'^#{1,6}\s+').hasMatch(trimmedLine)) {
      return true;
    }
    if (RegExp(r'^([-*+])\s+').hasMatch(trimmedLine)) {
      return true;
    }
    if (RegExp(r'^\d+\.\s+').hasMatch(trimmedLine)) {
      return true;
    }
    if (RegExp(r'^>\s?').hasMatch(trimmedLine)) {
      return true;
    }
    if (RegExp(r'^([-*_])(\s*\1){2,}\s*$').hasMatch(trimmedLine)) {
      return true;
    }
    return false;
  }

  static bool _isExternalHref(String href) =>
      href.startsWith('http://') || href.startsWith('https://');

  static List<Component> _parseBlocks(String markdown) {
    final normalized = markdown.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final blocks = <Component>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // 1. Fenced code block (``` or ~~~)
      final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})(.*)$').firstMatch(line);
      if (fenceMatch != null) {
        final fenceMarker = fenceMatch.group(1)!;
        final fenceChar = fenceMarker[0];
        final fenceLen = fenceMarker.length;
        final infoString = (fenceMatch.group(2) ?? '').trim();
        final language = infoString.split(RegExp(r'\s+')).first;
        i++;

        final codeLines = <String>[];
        final closePattern = RegExp(
          '^\\s*${RegExp.escape(fenceChar)}{$fenceLen,}\\s*\$',
        );
        while (i < lines.length && !closePattern.hasMatch(lines[i])) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) {
          i++; // Skip closing fence line
        }
        blocks.add(
          _buildCodeFenceBlock(
            code: codeLines.join('\n').trimRight(),
            language: language,
          ),
        );
        continue;
      }

      // 2. Horizontal rule (---, ***, ___)
      if (RegExp(r'^([-*_])(\s*\1){2,}\s*$').hasMatch(trimmed)) {
        blocks.add(
          Component.element(
            children: const [],
            classes: 'markdown-hr',
            tag: 'hr',
          ),
        );
        i++;
        continue;
      }

      // 3. Heading (# .. ######)
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
          .firstMatch(trimmed);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final headingText = headingMatch.group(2) ?? '';
        blocks.add(
          Component.element(
            children: _parseInlineNodes(headingText),
            classes: 'markdown-heading',
            tag: 'h$level',
          ),
        );
        i++;
        continue;
      }

      // 4. Blockquote (> ...)
      if (RegExp(r'^>\s?').hasMatch(trimmed)) {
        final quoteLines = <String>[];
        while (i < lines.length && RegExp(r'^\s*>\s?').hasMatch(lines[i])) {
          quoteLines.add(lines[i].replaceFirst(RegExp(r'^\s*>\s?'), ''));
          i++;
        }
        blocks.add(
          Component.element(
            children: _parseBlocks(quoteLines.join('\n')),
            classes: 'callout-box markdown-blockquote',
            tag: 'blockquote',
          ),
        );
        continue;
      }

      // 5. Unordered list (- / * / +)
      if (RegExp(r'^([-*+])\s+').hasMatch(trimmed)) {
        final items = <Component>[];
        while (i < lines.length) {
          final itemMatch = RegExp(r'^\s*([-*+])\s+(.*)$').firstMatch(lines[i]);
          if (itemMatch == null) {
            break;
          }
          final itemBuffer = <String>[itemMatch.group(2) ?? ''];
          i++;
          while (i < lines.length) {
            final nextTrimmed = lines[i].trim();
            if (nextTrimmed.isEmpty || _isBlockStart(nextTrimmed)) {
              break;
            }
            itemBuffer.add(nextTrimmed);
            i++;
          }
          items.add(
            Component.element(
              children: _parseInlineNodes(itemBuffer.join(' ')),
              tag: 'li',
            ),
          );
        }
        blocks.add(
          Component.element(
            children: items,
            classes: 'markdown-list',
            tag: 'ul',
          ),
        );
        continue;
      }

      // 6. Ordered list (1. ...)
      if (RegExp(r'^\d+\.\s+').hasMatch(trimmed)) {
        final items = <Component>[];
        while (i < lines.length) {
          final itemMatch = RegExp(r'^\s*\d+\.\s+(.*)$').firstMatch(lines[i]);
          if (itemMatch == null) {
            break;
          }
          final itemBuffer = <String>[itemMatch.group(1) ?? ''];
          i++;
          while (i < lines.length) {
            final nextTrimmed = lines[i].trim();
            if (nextTrimmed.isEmpty || _isBlockStart(nextTrimmed)) {
              break;
            }
            itemBuffer.add(nextTrimmed);
            i++;
          }
          items.add(
            Component.element(
              children: _parseInlineNodes(itemBuffer.join(' ')),
              tag: 'li',
            ),
          );
        }
        blocks.add(
          Component.element(
            children: items,
            classes: 'markdown-list',
            tag: 'ol',
          ),
        );
        continue;
      }

      // 7. Paragraph
      final paragraphLines = <String>[];
      while (i < lines.length) {
        final currentTrimmed = lines[i].trim();
        if (currentTrimmed.isEmpty || _isBlockStart(currentTrimmed)) {
          break;
        }
        paragraphLines.add(currentTrimmed);
        i++;
      }
      if (paragraphLines.isNotEmpty) {
        blocks.add(
          Component.element(
            children: _parseInlineNodes(paragraphLines.join(' ')),
            classes: 'markdown-paragraph',
            tag: 'p',
          ),
        );
      }
    }

    return blocks;
  }

  static List<Component> _parseInlineNodes(String input) {
    if (input.isEmpty) {
      return const <Component>[];
    }

    final nodes = <Component>[];
    final plainBuffer = StringBuffer();
    var index = 0;

    void flushPlain() {
      if (plainBuffer.isNotEmpty) {
        nodes.add(Component.text(plainBuffer.toString()));
        plainBuffer.clear();
      }
    }

    while (index < input.length) {
      final char = input[index];

      // 1. Inline code span (`...` or ``...``)
      if (char == '`') {
        var tickCount = 1;
        while (index + tickCount < input.length &&
            input[index + tickCount] == '`') {
          tickCount++;
        }
        final delimiter = '`' * tickCount;
        final closeIndex = input.indexOf(delimiter, index + tickCount);
        if (closeIndex != -1) {
          flushPlain();
          var codeText = input.substring(index + tickCount, closeIndex);
          if (codeText.length >= 2 &&
              codeText.startsWith(' ') &&
              codeText.endsWith(' ')) {
            codeText = codeText.substring(1, codeText.length - 1);
          }
          nodes.add(
            Component.element(
              children: [Component.text(codeText)],
              classes: 'inline-code',
              tag: 'code',
            ),
          );
          index = closeIndex + tickCount;
          continue;
        }
      }

      // 2. Autolink (<https://...> or <http://...>)
      if (char == '<') {
        final autoMatch = RegExp(r'^<(https?://[^>\s]+)>')
            .firstMatch(input.substring(index));
        if (autoMatch != null) {
          flushPlain();
          final url = autoMatch.group(1)!;
          nodes.add(
            Component.element(
              attributes: {
                'href': url,
                'rel': 'noopener noreferrer',
                'target': '_blank',
              },
              children: [Component.text(url)],
              classes: 'markdown-link',
              tag: 'a',
            ),
          );
          index += autoMatch.group(0)!.length;
          continue;
        }
      }

      // 3. Markdown link [label](url "optional title")
      if (char == '[') {
        final linkMatch = RegExp(
          r'^\[((?:`[^`]*`|[^\]])+)\]\(\s*([^\s")]+)(?:\s+"([^"]*)")?\s*\)',
        ).firstMatch(input.substring(index));
        if (linkMatch != null) {
          flushPlain();
          final label = linkMatch.group(1)!;
          final href = linkMatch.group(2)!;
          final title = linkMatch.group(3);
          final isExternal = _isExternalHref(href);
          nodes.add(
            Component.element(
              attributes: {
                'href': href,
                if (isExternal) 'rel': 'noopener noreferrer',
                if (isExternal) 'target': '_blank',
                if (title != null && title.isNotEmpty) 'title': title,
              },
              children: _parseInlineNodes(label),
              classes: 'markdown-link',
              tag: 'a',
            ),
          );
          index += linkMatch.group(0)!.length;
          continue;
        }
      }

      // 4. Strikethrough (~~...~~)
      if (input.startsWith('~~', index)) {
        final closeIndex = input.indexOf('~~', index + 2);
        if (closeIndex > index + 2) {
          flushPlain();
          final inner = input.substring(index + 2, closeIndex);
          nodes.add(
            Component.element(children: _parseInlineNodes(inner), tag: 'del'),
          );
          index = closeIndex + 2;
          continue;
        }
      }

      // 5. Bold + Italic (***...***)
      if (input.startsWith('***', index)) {
        final closeIndex = input.indexOf('***', index + 3);
        if (closeIndex > index + 3) {
          flushPlain();
          final inner = input.substring(index + 3, closeIndex);
          nodes.add(
            Component.element(
              children: [
                Component.element(
                  children: _parseInlineNodes(inner),
                  tag: 'em',
                ),
              ],
              tag: 'strong',
            ),
          );
          index = closeIndex + 3;
          continue;
        }
      }

      // 6. Bold (**...** or __...__)
      if (input.startsWith('**', index) || input.startsWith('__', index)) {
        final marker = input.substring(index, index + 2);
        final isUnderscore = marker == '__';
        final prevBoundaryOk =
            !isUnderscore ||
            index == 0 ||
            !_isAlphaNumeric(input.codeUnitAt(index - 1));
        if (prevBoundaryOk) {
          final closeIndex = input.indexOf(marker, index + 2);
          final nextBoundaryOk =
              closeIndex != -1 &&
              (!isUnderscore ||
                  closeIndex + 2 >= input.length ||
                  !_isAlphaNumeric(input.codeUnitAt(closeIndex + 2)));
          if (closeIndex > index + 2 && nextBoundaryOk) {
            flushPlain();
            final inner = input.substring(index + 2, closeIndex);
            nodes.add(
              Component.element(
                children: _parseInlineNodes(inner),
                tag: 'strong',
              ),
            );
            index = closeIndex + 2;
            continue;
          }
        }
      }

      // 7. Italic (*...* or _..._) with word-boundary check for '_'
      if (char == '*' || char == '_') {
        final isUnderscore = char == '_';
        final prevBoundaryOk =
            !isUnderscore ||
            index == 0 ||
            !_isAlphaNumeric(input.codeUnitAt(index - 1));
        final notWhitespaceAfterOpen =
            index + 1 < input.length &&
            input[index + 1] != ' ' &&
            input[index + 1] != char;
        if (prevBoundaryOk && notWhitespaceAfterOpen) {
          var closeIndex = input.indexOf(char, index + 1);
          while (closeIndex != -1) {
            final notWhitespaceBeforeClose = input[closeIndex - 1] != ' ';
            final nextBoundaryOk =
                !isUnderscore ||
                closeIndex + 1 >= input.length ||
                !_isAlphaNumeric(input.codeUnitAt(closeIndex + 1));
            if (notWhitespaceBeforeClose && nextBoundaryOk) {
              break;
            }
            closeIndex = input.indexOf(char, closeIndex + 1);
          }
          if (closeIndex > index + 1) {
            flushPlain();
            final inner = input.substring(index + 1, closeIndex);
            nodes.add(
              Component.element(children: _parseInlineNodes(inner), tag: 'em'),
            );
            index = closeIndex + 1;
            continue;
          }
        }
      }

      plainBuffer.write(char);
      index++;
    }

    flushPlain();
    return nodes;
  }

  @override
  Component build(BuildContext context) {
    final blocks = _parseBlocks(content);
    final resolvedClass = (classes != null && classes!.trim().isNotEmpty)
        ? '${classes!.trim()} markdown-content'
        : 'markdown-content';

    return Component.element(
      children: blocks,
      classes: resolvedClass,
      tag: 'div',
    );
  }
}
