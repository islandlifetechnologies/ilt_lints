import 'package:jaspr/jaspr.dart';

import 'markdown_content.dart';

/// Renders [content] with inline Markdown formatting (backtick code spans,
/// links `[text](url)`, bold, italic, and strikethrough).
class const InlineCodeText({required final String content, super.key})
    extends StatelessComponent {
  @override
  Component build(BuildContext context) =>
      Component.fragment(MarkdownContent.parseInline(content));
}
