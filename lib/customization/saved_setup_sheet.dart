import 'package:flutter/material.dart';

class SetupChoice {
  const SetupChoice({this.id, this.name});
  final String? id;
  final String? name;
}

String setupScopeLabel(String scope) => switch (scope) {
  'network' => 'Network indicator',
  'edge' => 'Panel & handle',
  _ => 'All device settings',
};

class SavedSetupSheet extends StatefulWidget {
  const SavedSetupSheet({
    super.key,
    required this.setups,
    this.scope = 'all',
    this.restore = false,
  });
  final List<Map<String, dynamic>> setups;
  final String scope;
  final bool restore;
  @override
  State<SavedSetupSheet> createState() => _SavedSetupSheetState();
}

class _SavedSetupSheetState extends State<SavedSetupSheet> {
  late bool create = widget.setups.isEmpty && !widget.restore;
  late String? selected = widget.setups.isEmpty
      ? null
      : widget.setups.first['id'] as String;
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height - inset;
    final canSubmit = create ? name.text.trim().isNotEmpty : selected != null;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: (available * .9).clamp(240, 680).toDouble(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        widget.restore
                            ? Icons.restore_rounded
                            : Icons.bookmark_add_outlined,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.restore
                                ? 'Restore setup'
                                : 'Save your setup',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.restore
                                ? widget.scope == 'all'
                                      ? 'Return to a familiar setup'
                                      : setupScopeLabel(widget.scope)
                                : setupScopeLabel(widget.scope),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  children: [
                    if (!widget.restore && widget.setups.isNotEmpty) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Update existing'),
                            icon: Icon(Icons.edit_outlined),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Create new'),
                            icon: Icon(Icons.add),
                          ),
                        ],
                        selected: {create},
                        onSelectionChanged: (value) =>
                            setState(() => create = value.first),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      widget.restore
                          ? widget.scope == 'all'
                                ? 'Your current settings will be kept in a recovery checkpoint before restoring.'
                                : 'Restore only ${setupScopeLabel(widget.scope).toLowerCase()} from this setup. Your other current settings stay unchanged. A recovery checkpoint is kept first.'
                          : create
                          ? 'Create a complete snapshot of your current device customization.'
                          : widget.scope == 'all'
                          ? 'Replace the selected setup with your current device settings.'
                          : 'Update only ${setupScopeLabel(widget.scope).toLowerCase()} in the selected setup. Its other settings stay as saved.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (create)
                      TextField(
                        controller: name,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (canSubmit) {
                            Navigator.pop(
                              context,
                              SetupChoice(name: name.text.trim()),
                            );
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Setup name',
                          hintText: 'Everyday, Minimal, Travel…',
                          prefixIcon: const Icon(
                            Icons.bookmark_outline_rounded,
                          ),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    if (!create && widget.setups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.bookmarks_outlined,
                              size: 44,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            const Text('Your setups will appear here'),
                            const SizedBox(height: 4),
                            Text(
                              'Save your first setup to keep a version you like.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    if (!create)
                      for (final item in widget.setups) ...[
                        Builder(
                          builder: (context) {
                            final active = selected == item['id'];
                            final at = DateTime.fromMillisecondsSinceEpoch(
                              (item['updatedAt'] ?? item['at']) as int,
                            ).toLocal();
                            final local = MaterialLocalizations.of(context);
                            return Material(
                              color: active
                                  ? colors.secondaryContainer
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => setState(
                                  () => selected = item['id'] as String,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        active
                                            ? Icons.check_circle_rounded
                                            : Icons.bookmark_border_rounded,
                                        color: active
                                            ? colors.onSecondaryContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item['name']}',
                                              style:
                                                  theme.textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${local.formatMediumDate(at)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            if (item['feature'] != null &&
                                                item['feature'] != 'all') ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '${setupScopeLabel(item['feature'] as String)} updated',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: !canSubmit
                      ? null
                      : () => Navigator.pop(
                          context,
                          create
                              ? SetupChoice(name: name.text.trim())
                              : SetupChoice(id: selected),
                        ),
                  icon: Icon(
                    widget.restore
                        ? Icons.restore_rounded
                        : create
                        ? Icons.add_rounded
                        : Icons.save_outlined,
                  ),
                  label: Text(
                    widget.restore
                        ? widget.scope == 'all'
                              ? 'Restore selected setup'
                              : 'Restore ${setupScopeLabel(widget.scope).toLowerCase()}'
                        : create
                        ? 'Save new setup'
                        : 'Update selected setup',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
