import 'package:PiliPlus/models_new/download/download_sort.dart';
import 'package:material_ui/material_ui.dart';

Future<DownloadSort?> chooseDownloadSort(
  BuildContext context,
  DownloadSort current,
) => showDialog<DownloadSort>(
  context: context,
  builder: (context) {
    var value = current;
    return StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('排序'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final field in DownloadSortField.values)
                    ChoiceChip(
                      label: Text(field.label),
                      selected: value.field == field,
                      onSelected: (_) => update(
                        () =>
                            value = (field: field, ascending: value.ascending),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final ascending in [true, false])
                    ChoiceChip(
                      label: Text(ascending ? '升序' : '降序'),
                      selected: value.ascending == ascending,
                      onSelected: (_) => update(
                        () =>
                            value = (field: value.field, ascending: ascending),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  },
);
