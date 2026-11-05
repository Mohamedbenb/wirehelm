String statefulTargetPlaceholder(
  String key,
) {
  return '{{target:$key}}';
}

final RegExp _targetPlaceholderPattern =
    RegExp(
  r'\{\{target:([A-Za-z_][A-Za-z0-9_-]*)\}\}',
);

Set<String> statefulTargetPlaceholders(
  String template,
) {
  return _targetPlaceholderPattern
      .allMatches(
        template,
      )
      .map(
        (match) =>
            match.group(1)!,
      )
      .toSet();
}

String renderStatefulTemplate(
  String template, {
  String? targetKey,
  String? targetValue,
}) {
  var result =
      template;

  if (targetKey != null &&
      targetValue != null) {
    result =
        result.replaceAll(
      statefulTargetPlaceholder(
        targetKey,
      ),
      targetValue,
    );
  }

  return result.trim();
}