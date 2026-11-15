import 'package:jaspr/jaspr.dart';

/// Renders [content] while converting markdown-style backtick spans (`` `...` ``)
/// into HTML `<code>` elements.
class const InlineCodeText({required final String content, super.key})
    extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    final parts = content.split('`');
    if (parts.length == 1) {
      return Component.text(content);
    }

    final children = <Component>[];
    for (var i = 0; i < parts.length; i++) {
      final segment = parts[i];
      if (segment.isEmpty) {
        continue;
      }
      if (i.isOdd && i < parts.length - 1) {
        children.add(
          Component.element(
            children: [Component.text(segment)],
            classes: 'inline-code',
            tag: 'code',
          ),
        );
      } else {
        children.add(Component.text(segment));
      }
    }
    return Component.fragment(children);
  }
}
