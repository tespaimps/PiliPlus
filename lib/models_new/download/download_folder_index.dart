import 'dart:collection';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:collection/collection.dart';

class DownloadFolderLayout {
  final Map<String, String> names;
  final Map<String, String> destinations;

  DownloadFolderLayout({
    Map<String, String>? names,
    Map<String, String>? destinations,
  }) : names = names ?? {},
       destinations = destinations ?? {};

  factory DownloadFolderLayout.fromJson(Object? data) {
    if (data == null) return DownloadFolderLayout();
    if (data is! Map || data['version'] != 1) {
      throw const FormatException('Unsupported offline folder layout');
    }
    return DownloadFolderLayout(
      names: Map<String, String>.from(data['names'] as Map),
      destinations: Map<String, String>.from(data['destinations'] as Map),
    );
  }

  DownloadFolderLayout copy() => DownloadFolderLayout(
    names: Map.of(names),
    destinations: Map.of(destinations),
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'names': names,
    'destinations': destinations,
  };
}

class DownloadFolderSelection {
  final String? scope;
  final Map<String, Set<String>> locations;
  final String firstTitle;

  DownloadFolderSelection(this.scope, this.locations, this.firstTitle);

  int get count => locations.length;
  late final Set<String> sources = {
    for (final groups in locations.values) ...groups,
  };
}

class DownloadFolderException implements Exception {
  final String message;
  const DownloadFolderException(this.message);
}

class DownloadSearchVideo {
  final DownloadSeasonInfo card;
  final Set<String> _terms = {};
  final Map<String, String> _parts = {};

  DownloadSearchVideo(this.card) {
    for (final page in card.pages) {
      for (final entry in page.entries) {
        for (final text in [
          entry.title,
          entry.ownerName,
          entry.seasonInfo?.uname,
        ]) {
          if (text != null) _terms.add(text.toLowerCase());
        }
        final part = entry.showTitle;
        if (part != entry.title) _parts[part] = part.toLowerCase();
      }
    }
  }

  bool matches(String query) =>
      _terms.any((term) => term.contains(query)) ||
      _parts.values.any((part) => part.contains(query));

  String? matchingPart(String query) {
    for (final part in _parts.entries) {
      if (part.value.contains(query)) return part.key;
    }
    return null;
  }
}

typedef _Member = ({
  int rank,
  DownloadSeasonInfo season,
  DownloadPageInfo page,
  String autoKey,
  String autoName,
});

class _Bucket {
  final members = <int, _Member>{};
  DownloadOwnerGroup? group;
  DownloadOwnerFolder? folder;
  int? firstRank;
  int explicitCount = 0;
}

class DownloadFolderIndex {
  final List<DownloadSeasonInfo> seasons;
  DownloadFolderLayout _layout;
  final _videos = <String, List<_Member>>{};
  final _buckets = <String, _Bucket>{};
  final _rootOrder = SplayTreeMap<int, String>();
  final _folderOrder = SplayTreeMap<int, String>();
  final _pagesByPath = <String, DownloadPageInfo>{};
  final _collections = <(String?, int), DownloadSeasonInfo>{};
  final _originalGroups = <String, String>{};
  late final searchVideos = Map<String, DownloadSearchVideo>.unmodifiable({
    for (final entry in _videos.entries)
      entry.key: DownloadSearchVideo(_searchCard(entry.value)),
  });

  DownloadSeasonInfo _searchCard(List<_Member> members) {
    final page = members.first.page;
    return DownloadSeasonInfo(
      seasonInfo: null,
      pageId: page.pageId,
      pages: List.unmodifiable(
        {
          for (final member in members)
            member.page.dirPath: _pagesByPath[member.page.dirPath]!,
        }.values,
      ),
    );
  }

  DownloadFolderIndex(Iterable<BiliDownloadEntryInfo> entries, this._layout)
    : seasons = buildDownloadSeasons(entries) {
    var rank = 0;
    final splitPages = <String, List<DownloadPageInfo>>{};
    for (final season in seasons) {
      final (:key, :name) = downloadOwnerIdentity(season);
      if (season.seasonInfo case final info?) {
        _collections[(null, info.id)] = season;
      }
      for (final page in season.pages) {
        final video = downloadVideoKey(page);
        final member = (
          rank: rank++,
          season: season,
          page: page,
          autoKey: key,
          autoName: name,
        );
        (_videos[video] ??= []).add(member);
        final firstPage = _pagesByPath.putIfAbsent(page.dirPath, () => page);
        if (!identical(firstPage, page)) {
          (splitPages[page.dirPath] ??= [firstPage]).add(page);
        }
        _originalGroups.putIfAbsent(key, () => name);
        final target = _layout.destinations[video];
        final bucket = _buckets.putIfAbsent(target ?? key, _Bucket.new);
        bucket.members[member.rank] = member;
        if (target != null) bucket.explicitCount++;
      }
    }
    for (final pages in splitPages.values) {
      final first = pages.first;
      final entries = <int, BiliDownloadEntryInfo>{};
      for (final page in pages) {
        for (final entry in page.entries) {
          entries.putIfAbsent(entry.cid, () => entry);
        }
      }
      _pagesByPath[first.dirPath] = DownloadPageInfo(
        pageId: first.pageId,
        dirPath: first.dirPath,
        title: first.title,
        cover: first.cover,
        sortKey: first.sortKey,
        seasonType: first.seasonType,
        entries: List.unmodifiable(entries.values),
      );
    }
    for (final key in _buckets.keys) {
      _refresh(key, ordered: true);
    }
  }

  Iterable<DownloadOwnerFolder> get folders sync* {
    for (final key in _folderOrder.values) {
      yield _buckets[key]!.folder!;
    }
  }

  DownloadOwnerFolder? folder(String key) => _buckets[key]?.folder;
  DownloadPageInfo? pageAt(String dirPath) => _pagesByPath[dirPath];
  DownloadSeasonInfo? collection(String? folderKey, int id) =>
      _collections[(folderKey, id)];
  String? originalName(String key) => _originalGroups[key];

  Set<String> locations(String video) => {
    for (final member in _videos[video] ?? const <_Member>[])
      _layout.destinations[video] ?? member.autoKey,
  };

  DownloadListSnapshot snapshot() => DownloadListSnapshot(
    seasons,
    List.unmodifiable([
      for (final key in _rootOrder.values)
        if (_buckets[key]!.folder case final folder?)
          folder
        else
          ..._buckets[key]!.group!.seasons,
    ]),
    Map.unmodifiable({
      for (final entry in _buckets.entries) entry.key: entry.value.group!,
    }),
  );

  /// Remove only groups that this transaction will empty.
  void pruneEmptiedFolders(DownloadFolderLayout next, Set<String> videos) {
    final removed = <String, int>{};
    for (final video in videos) {
      final source = _layout.destinations[video];
      if (source != null &&
          source.startsWith('manual:') &&
          source != next.destinations[video]) {
        removed.update(
          source,
          (count) => count + _videos[video]!.length,
          ifAbsent: () => _videos[video]!.length,
        );
      }
    }
    for (final entry in removed.entries) {
      if (_buckets[entry.key]?.members.length == entry.value) {
        next.names.remove(entry.key);
      }
    }
  }

  void apply(
    DownloadFolderLayout next, {
    Set<String> moved = const {},
    String? renamed,
  }) {
    final affected = <String>{};
    for (final video in moved) {
      final previous = _layout.destinations[video];
      final target = next.destinations[video]!;
      if (previous == target) continue;
      for (final member in _videos[video]!) {
        final source = previous ?? member.autoKey;
        final from = _buckets[source]!;
        from.members.remove(member.rank);
        if (previous != null) from.explicitCount--;
        final to = _buckets.putIfAbsent(target, _Bucket.new);
        to.members[member.rank] = member;
        to.explicitCount++;
        affected.addAll([source, target]);
      }
    }
    _layout = next;
    for (final key in affected) {
      final bucket = _buckets[key]!;
      if (bucket.firstRank case final rank?) {
        _rootOrder.remove(rank);
        _folderOrder.remove(rank);
        bucket.firstRank = null;
      }
    }
    for (final key in affected) {
      _refresh(key);
    }
    if (renamed != null) {
      final bucket = _buckets[renamed]!;
      final folder = DownloadOwnerFolder.withName(
        bucket.folder!,
        next.names[renamed]!,
      );
      bucket
        ..group = folder.group
        ..folder = folder;
    }
  }

  void _refresh(String key, {bool ordered = false}) {
    final bucket = _buckets[key]!;
    final oldRank = bucket.firstRank;
    if (oldRank != null) {
      _rootOrder.remove(oldRank);
      _folderOrder.remove(oldRank);
    }
    for (final season
        in bucket.group?.seasons ?? const <DownloadSeasonInfo>[]) {
      if (season.seasonInfo case final info?) {
        _collections.remove((key, info.id));
      }
    }
    if (bucket.members.isEmpty) {
      _buckets.remove(key);
      return;
    }
    final members = ordered
        ? bucket.members.values
        : bucket.members.values.sortedBy<num>((member) => member.rank);
    final sections = <DownloadSeasonInfo, List<DownloadPageInfo>>{};
    String? nativeName;
    for (final member in members) {
      (sections[member.season] ??= []).add(member.page);
      if (member.autoKey == key) nativeName ??= member.autoName;
    }
    final visible = [
      for (final section in sections.entries)
        DownloadSeasonInfo(
          pageId: section.value.first.pageId,
          seasonInfo: section.key.seasonInfo,
          pages: List.unmodifiable(section.value),
          folderKey: key,
        ),
    ];
    for (final season in visible) {
      if (season.seasonInfo case final info?) {
        _collections[(key, info.id)] = season;
      }
    }
    final first = members.first;
    final name =
        _layout.names[key] ??
        nativeName ??
        _originalGroups[key] ??
        first.autoName;
    final group = summarizeDownloadGroup(key, name, visible);
    final isFolder =
        key.startsWith('manual:') ||
        bucket.explicitCount > 0 ||
        (!key.startsWith('unknown:') && group.videoCount > 1);
    bucket
      ..firstRank = first.rank
      ..group = group
      ..folder = isFolder ? DownloadOwnerFolder(group) : null;
    _rootOrder[first.rank] = key;
    if (isFolder) _folderOrder[first.rank] = key;
  }
}
