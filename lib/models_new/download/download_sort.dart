import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';

enum DownloadSortField {
  name('名称'),
  created('创建日期'),
  size('大小'),
  type('类型');

  const DownloadSortField(this.label);
  final String label;
}

typedef DownloadSort = ({DownloadSortField field, bool ascending});
const defaultDownloadSort = (
  field: DownloadSortField.created,
  ascending: false,
);

DownloadSort decodeDownloadSort(Object? data) {
  if (data is List &&
      data.length == 2 &&
      data[0] is String &&
      data[1] is bool) {
    for (final field in DownloadSortField.values) {
      if (field.name == data[0]) {
        return (field: field, ascending: data[1] as bool);
      }
    }
  }
  return defaultDownloadSort;
}

final _stats = Expando<({int oldest, int newest, int bytes})>();
final _names = Expando<String>();
final _keys = Expando<String>();

String downloadCardName(DownloadSeasonInfo item) => item is DownloadOwnerFolder
    ? item.group.name
    : item.pages.length > 1 && item.seasonInfo != null
    ? item.seasonInfo!.title
    : item.pages.first.title;

({int oldest, int newest, int bytes}) _measure(DownloadSeasonInfo item) {
  if (item is DownloadOwnerFolder) {
    final group = item.group;
    return (
      oldest: group.oldest,
      newest: group.newest,
      bytes: group.totalBytes,
    );
  }
  var oldest = 0;
  var newest = 0;
  var bytes = 0;
  final seen = <int>{};
  for (final page in item.pages) {
    for (final entry in page.entries) {
      final date = entry.timeCreateStamp;
      if (date > 0 && (oldest == 0 || date < oldest)) oldest = date;
      if (date > newest) newest = date;
      if (seen.add(entry.cid)) bytes += entry.totalBytes;
    }
  }
  return (oldest: oldest, newest: newest, bytes: bytes);
}

int _type(DownloadSeasonInfo item) => item is DownloadOwnerFolder
    ? 2
    : item.seasonInfo != null && item.pages.length > 1
    ? 1
    : 0;

int _compareDates(int a, int b, bool ascending) {
  if (a == b) return 0;
  if (a == 0) return 1;
  if (b == 0) return -1;
  return ascending ? a.compareTo(b) : b.compareTo(a);
}

List<T> sortDownloads<T extends DownloadSeasonInfo>(
  Iterable<T> items,
  DownloadSort sort,
) {
  return items.toList()..sort((a, b) {
    final x = _stats[a.pages] ??= _measure(a);
    final y = _stats[b.pages] ??= _measure(b);
    final ascending = sort.ascending;
    final order = switch (sort.field) {
      DownloadSortField.name =>
        (_names[a] ??= downloadCardName(a).trim().toLowerCase()).compareTo(
          _names[b] ??= downloadCardName(b).trim().toLowerCase(),
        ),
      DownloadSortField.created => _compareDates(
        ascending ? x.oldest : x.newest,
        ascending ? y.oldest : y.newest,
        ascending,
      ),
      DownloadSortField.size => x.bytes.compareTo(y.bytes),
      DownloadSortField.type => _type(a).compareTo(_type(b)),
    };
    if (order != 0) {
      return ascending || sort.field == DownloadSortField.created
          ? order
          : -order;
    }
    final date = _compareDates(x.newest, y.newest, false);
    return date != 0
        ? date
        : (_keys[a] ??= downloadCardSelectionKey(a)).compareTo(
            _keys[b] ??= downloadCardSelectionKey(b),
          );
  });
}
