// HINT: Unnecessary import. Future and Stream are available via dart:core.
import 'dart:async';
import 'dart:typed_data';
import 'package:idb_shim/idb.dart';
import 'package:meta/meta.dart';
import 'package:flutter_cache_manager/src/cache_object.dart';
import 'package:flutter_cache_manager/src/cache_store.dart';
import 'package:flutter_cache_manager/src/file_fetcher.dart';
import 'package:flutter_cache_manager/src/file_info.dart';
import 'package:flutter_cache_manager/src/web_helper.dart';
import 'package:fs_shim/fs.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

///Flutter Cache Manager
///Copyright (c) 2019 Rene Floor
///Released under MIT License.

class DefaultCacheManager extends BaseCacheManager {
  final String path;
  static const key = "libCachedImageData";

  static DefaultCacheManager _instance;

  factory DefaultCacheManager.create(
          {@required FileSystem fs,
          @required IdbFactory idbFactory,
          @required String path}) =>
      DefaultCacheManager(fs: fs, idbFactory: idbFactory, path: path);

  /// The DefaultCacheManager that can be easily used directly. The code of
  /// this implementation can be used as inspiration for more complex cache
  /// managers.
  ///
  /// [tmpPath] is a directory name
  factory DefaultCacheManager(
      {FileSystem fs, IdbFactory idbFactory, String path}) {
    if (_instance == null) {
      assert(fs != null,
          "DefaultCacheManager should have been initialized before with a proper FileSystem to use");
      assert(path != null,
          "DefaultCacheManager should have been initialized before with a proper path to use");
      assert(idbFactory != null,
          "DefaultCacheManager should have been initialized before with a proper idbFactory to use");
      _instance = new DefaultCacheManager._(fs, idbFactory, path);
    }
    return _instance;
  }

  DefaultCacheManager._(FileSystem fs, IdbFactory idbFactory, this.path)
      : super(fs, idbFactory, key);

  Future<String> getFilePath() async {
    return p.join(path, key);
  }
}

abstract class BaseCacheManager {
  final FileSystem fs;
  final IdbFactory idbFactory;
  Future<String> _fileBasePath;

  /// Creates a new instance of a cache manager. This can be used to retrieve
  /// files from the cache or download them online. The http headers are used
  /// for the maximum age of the files. The BaseCacheManager should only be
  /// used in singleton patterns.
  ///
  /// The [_cacheKey] is used for the sqlite database file and should be unique.
  /// Files are removed when they haven't been used for longer than [_maxAgeCacheObject]
  /// or when this cache has grown to big. When the cache is larger than [_maxNrOfCacheObjects]
  /// files the files that haven't been used longest will be removed.
  /// The [httpGetter] can be used to customize how files are downloaded. For example
  /// to edit the urls, add headers or use a proxy.
  BaseCacheManager(this.fs, this.idbFactory, this._cacheKey,
      {Duration maxAgeCacheObject = const Duration(days: 30),
      int maxNrOfCacheObjects = 200,
      FileFetcher fileFetcher}) {
    _fileBasePath = getFilePath();

    _maxAgeCacheObject = maxAgeCacheObject;
    _maxNrOfCacheObjects = maxNrOfCacheObjects;
    _store = new CacheStore(fs, idbFactory, _fileBasePath, _cacheKey,
        _maxNrOfCacheObjects, _maxAgeCacheObject);
    _webHelper = new WebHelper(_store, fileFetcher);
  }

  final String _cacheKey;
  Duration _maxAgeCacheObject;
  int _maxNrOfCacheObjects;

  /// This path is used as base folder for all cached files.
  Future<String> getFilePath();

  /// Store helper for cached files
  CacheStore _store;

  /// Webhelper to download and store files
  WebHelper _webHelper;

  /// Get the file from the cache and/or online, depending on availability and age.
  /// Downloaded form [url], [headers] can be used for example for authentication.
  /// When a file is cached it is return directly, when it is too old the file is
  /// downloaded in the background. When a cached file is not available the
  /// newly downloaded file is returned.
  Future<File> getSingleFile(String url, {Map<String, String> headers}) async {
    var cacheFile = await getFileFromCache(url);
    if (cacheFile != null) {
      if (cacheFile.validTill.isBefore(DateTime.now())) {
        _webHelper.downloadFile(url, authHeaders: headers);
      }
      return cacheFile.file;
    }
    try {
      var download = await _webHelper.downloadFile(url, authHeaders: headers);
      return download.file;
    } catch (e) {
      return null;
    }
  }

  /// Get the file from the cache and/or online, depending on availability and age.
  /// Downloaded form [url], [headers] can be used for example for authentication.
  /// The files are returned as stream. First the cached file if available, when the
  /// cached file is too old the newly downloaded file is returned afterwards.
  Stream<FileInfo> getFile(String url, {Map<String, String> headers}) {
    var streamController = new StreamController<FileInfo>();
    _pushFileToStream(streamController, url, headers);
    return streamController.stream;
  }

  _pushFileToStream(StreamController streamController, String url,
      Map<String, String> headers) async {
    FileInfo cacheFile;
    try {
      cacheFile = await getFileFromCache(url);
      if (cacheFile != null) {
        streamController.add(cacheFile);
      }
    } catch (e) {
      print(
          "CacheManager: Failed to load cached file for $url with error:\n$e");
    }
    if (cacheFile == null || cacheFile.validTill.isBefore(DateTime.now())) {
      try {
        var webFile = await _webHelper.downloadFile(url, authHeaders: headers);
        if (webFile != null) {
          streamController.add(webFile);
        }
      } catch (e) {
        assert(() {
          print(
              "CacheManager: Failed to download file from $url with error:\n$e");
          return true;
        }());
        if (cacheFile == null && streamController.hasListener) {
          streamController.addError(e);
        }
      }
    }
    streamController.close();
  }

  ///Download the file and add to cache
  Future<FileInfo> downloadFile(String url,
      {Map<String, String> authHeaders, bool force = false}) async {
    return await _webHelper.downloadFile(url,
        authHeaders: authHeaders, ignoreMemCache: force);
  }

  ///Get the file from the cache
  Future<FileInfo> getFileFromCache(String url) async {
    return await _store.getFile(url);
  }

  ///Returns the file from memory if it has already been fetched
  FileInfo getFileFromMemory(String url) {
    return _store.getFileFromMemory(url);
  }

  /// Put a file in the cache. It is recommended to specify the [eTag] and the
  /// [maxAge]. When [maxAge] is passed and the eTag is not set the file will
  /// always be downloaded again. The [fileExtension] should be without a dot,
  /// for example "jpg". When cache info is available for the url that path
  /// is re-used.
  /// The returned [File] is saved on disk.
  Future<File> putFile(String url, Uint8List fileBytes,
      {String eTag,
      Duration maxAge = const Duration(days: 30),
      String fileExtension = "file"}) async {
    var cacheObject = await _store.retrieveCacheData(url);
    if (cacheObject == null) {
      var relativePath = "${new Uuid().v1()}.$fileExtension";
      cacheObject = new CacheObject(url, relativePath: relativePath);
    }
    cacheObject.validTill = DateTime.now().add(maxAge);
    cacheObject.eTag = eTag;

    var path = p.join(await getFilePath(), cacheObject.relativePath);
    var folder = fs.file(path).parent;
    if (!(await folder.exists())) {
      await folder.create(recursive: true);
    }
    var file = await fs.file(path).writeAsBytes(fileBytes);

    _store.putFile(cacheObject);

    return file;
  }

  /// Remove a file from the cache
  removeFile(String url) async {
    var cacheObject = await _store.retrieveCacheData(url);
    if (cacheObject != null) {
      await _store.removeCachedFile(cacheObject);
    }
  }

  /// Removes all files from the cache
  emptyCache() async {
    await _store.emptyCache();
  }
}
