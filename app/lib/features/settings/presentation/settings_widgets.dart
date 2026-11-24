import 'package:material_ui/material_ui.dart';

import '../../../data/publication_settings.dart';

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hint = subtitle;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: hint == null ? null : Text(hint),
      value: value,
      onChanged: onChanged,
    );
  }
}

class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hint = subtitle;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: hint == null ? null : Text(hint),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuer',
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Augmenter',
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// Choix unique parmi quelques options (puces).
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = Map<String, String>.of(options);
    if (!entries.containsKey(value)) {
      entries[value] = value;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in entries.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: entry.key == value,
                onSelected: (_) => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

/// Choix dans une longue liste, via une feuille modale.
class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final all = options.contains(value) ? options : [value, ...options];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.expand_more),
      onTap: () async {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in all)
                  ListTile(
                    title: Text(option),
                    trailing: option == value ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
              ],
            ),
          ),
        );
        if (choice != null) {
          onChanged(choice);
        }
      },
    );
  }
}

/// Liste de mots-clés modifiable (thématiques, catégories…).
class TagEditor extends StatefulWidget {
  const TagEditor({
    super.key,
    required this.label,
    required this.hint,
    required this.tags,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    var text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (text.length > 60) {
      text = text.substring(0, 60);
    }
    final exists =
        widget.tags.any((t) => t.toLowerCase() == text.toLowerCase());
    if (!exists && widget.tags.length < 30) {
      widget.onChanged([...widget.tags, text]);
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        if (widget.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in widget.tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => widget.onChanged(
                      widget.tags.where((t) => t != tag).toList(),
                    ),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: IconButton(
              tooltip: 'Ajouter',
              onPressed: _add,
              icon: const Icon(Icons.add),
            ),
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    );
  }
}

TimeOfDay timeOfDayFrom(String hhmm) {
  final total = minutesOf(hhmm);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

String hhmmFrom(TimeOfDay time) => formatMinutes(time.hour * 60 + time.minute);

/// Liste d’heures de publication.
class TimeListEditor extends StatelessWidget {
  const TimeListEditor({
    super.key,
    required this.label,
    required this.times,
    required this.onChanged,
  });

  final String label;
  final List<String> times;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = times.toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final time in sorted)
              InputChip(
                label: Text(time),
                onDeleted: () =>
                    onChanged(sorted.where((t) => t != time).toList()),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
                if (picked != null) {
                  onChanged([...sorted, hhmmFrom(picked)]);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Créneaux autorisés (début → fin).
class WindowsEditor extends StatelessWidget {
  const WindowsEditor({
    super.key,
    required this.label,
    required this.windows,
    required this.onChanged,
  });

  final String label;
  final List<TimeWindow> windows;
  final ValueChanged<List<TimeWindow>> onChanged;

  List<TimeWindow> _copy() =>
      [for (final w in windows) TimeWindow(start: w.start, end: w.end)];

  Future<void> _pick(
    BuildContext context,
    int index, {
    required bool isStart,
  }) async {
    final current = isStart ? windows[index].start : windows[index].end;
    final picked = await showTimePicker(
      context: context,
      initialTime: timeOfDayFrom(current),
    );
    if (picked == null) {
      return;
    }
    final next = _copy();
    if (isStart) {
      next[index].start = hhmmFrom(picked);
    } else {
      next[index].end = hhmmFrom(picked);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        for (var i = 0; i < windows.length; i++)
          Row(
            children: [
              TextButton(
                onPressed: () => _pick(context, i, isStart: true),
                child: Text(windows[i].start),
              ),
              const Icon(Icons.arrow_forward, size: 18),
              TextButton(
                onPressed: () => _pick(context, i, isStart: false),
                child: Text(windows[i].end),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Supprimer le créneau',
                onPressed: windows.length > 1
                    ? () => onChanged(
                          [
                            for (var j = 0; j < windows.length; j++)
                              if (j != i) windows[j],
                          ],
                        )
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => onChanged(
              [..._copy(), TimeWindow(start: '09:00', end: '12:00')],
            ),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un créneau'),
          ),
        ),
      ],
    );
  }
}
