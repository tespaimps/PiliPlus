import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:material_ui/material_ui.dart';

Future<String?> askDownloadFolderName(BuildContext context, {String? current}) {
  var name = current ?? '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        void submit() {
          if (name.trim().isNotEmpty) Navigator.of(context).pop(name.trim());
        }

        return AlertDialog(
          title: Text(current == null ? '命名合并文件夹' : '重命名文件夹'),
          content: TextFormField(
            initialValue: current,
            autofocus: true,
            decoration: const InputDecoration(labelText: '文件夹名称'),
            onChanged: (value) => setDialogState(() => name = value),
            onFieldSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: name.trim().isEmpty ? null : submit,
              child: const Text('确定'),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool?> confirmDownloadFolderMove(
  BuildContext context,
  DownloadFolderSelection selection,
  DownloadOwnerFolder folder,
) {
  final named = '“${selection.firstTitle}”';
  final videos = selection.count == 1
      ? named
      : '$named 等 ${selection.count} 个视频';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('确定将$videos 放入“${folder.group.name}”文件夹中？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('否'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('是'),
        ),
      ],
    ),
  );
}
