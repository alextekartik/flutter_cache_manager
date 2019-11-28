// CacheManager for Flutter
// Copyright (c) 2017 Rene Floor
// Released under MIT License.

// HINT: Unnecessary import. Future and Stream are available via dart:core.
import 'dart:async';

import 'package:idb_shim/idb.dart';

final String tableCacheObject = "cacheObject";

final String columnId = "_id";
final String columnUrl = "url";
final String columnPath = "relativePath";
final String columnETag = "eTag";
final String columnValidTill = "validTill";
final String columnTouched = "touched";
/**
 *  Flutter Cache Manager
 *
 *  Copyright (c) 2018 Rene Floor
 *
 *  Released under MIT License.
 */

///Cache information of one file
class CacheObject {
  int id;
  String url;
  String relativePath;
  DateTime validTill;
  String eTag;

  CacheObject(this.url,
      {this.relativePath, this.validTill, this.eTag, this.id});

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      columnUrl: url,
      columnPath: relativePath,
      columnETag: eTag,
      columnValidTill: validTill?.millisecondsSinceEpoch ?? 0,
      columnTouched: DateTime.now().millisecondsSinceEpoch
    };
    return map;
  }

  CacheObject.fromMap(int id, Map map) {
    this.id = id;
    url = map[columnUrl];
    relativePath = map[columnPath];
    validTill = DateTime.fromMillisecondsSinceEpoch(map[columnValidTill]);
    eTag = map[columnETag];
  }
}

class CacheObjectProvider {
  final IdbFactory idbFactory;
  Database db;
  String path;

  CacheObjectProvider(this.idbFactory, this.path);

  Future open() async {
    db = await idbFactory.open(path, version: 2, onUpgradeNeeded: (e) async {
      var db = e.database;
      if (e.oldVersion < e.newVersion) {
        try {
          db.deleteObjectStore(tableCacheObject);
        } catch (_) {}
        var store = db.createObjectStore(tableCacheObject, autoIncrement: true);
        store.createIndex(columnUrl, columnUrl);
      }
      /*
      await db.execute('''
      create table $tableCacheObject (
        $columnId integer primary key,
        $columnUrl text,
        $columnPath text,
        $columnETag text,
        $columnValidTill integer,
        $columnTouched integer
        )
      ''');

       */
    });
  }

  Future<dynamic> updateOrInsert(CacheObject cacheObject) async {
    if (cacheObject.id == null) {
      return await insert(cacheObject);
    } else {
      return await update(cacheObject);
    }
  }

  Transaction get _writeTransaction {
    return db.transaction(tableCacheObject, idbModeReadWrite);
  }

  ObjectStore get _writeStore {
    return _writeTransaction.objectStore(tableCacheObject);
  }

  Transaction get _readTransaction {
    return db.transaction(tableCacheObject, idbModeReadOnly);
  }

  ObjectStore get _readStore {
    return _readTransaction.objectStore(tableCacheObject);
  }

  Index get _byUrlIndex {
    return _readStore.index(columnUrl);
  }

  Future<CacheObject> insert(CacheObject cacheObject) async {
    cacheObject.id = await _writeStore.add(cacheObject.toMap());
    return cacheObject;
  }

  Future<CacheObject> get(String url) async {
    var index = _byUrlIndex;
    var first = await index.get(url);
    if (first is Map) {
      return new CacheObject.fromMap((await index.getKey(url)) as int, first);
    }
    return null;
  }

  Future<int> delete(int id) async {
    return await _writeStore.delete(id);
  }

  Future deleteAll(Iterable<int> ids) async {
    var store = _writeStore;
    for (int id in ids) {
      await store.delete(id);
    }
  }

  Future<int> update(CacheObject cacheObject) async {
    return await _writeStore.put(cacheObject.toMap(), cacheObject.id);
  }

  Future<List<CacheObject>> getAllObjects() async {
    var cacheObjects = <CacheObject>[];
    _writeStore.openCursor(autoAdvance: true).listen((data) {
      var value = data.value;
      if (value is Map) {
        cacheObjects.add(CacheObject.fromMap(data.key, value));
      }
    });
    return cacheObjects;
  }

  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async {
    return await getOldObjects(Duration(days: 1));
  }

  Future<List<CacheObject>> getOldObjects(Duration maxAge) async {
    var cacheObjects = <CacheObject>[];
    var date = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    _writeStore.openCursor(autoAdvance: true).listen((data) {
      var value = data.value;
      if (cacheObjects.length < 100) {
        if (value is Map) {
          if (value[columnTouched] as int < date) {
            cacheObjects.add(CacheObject.fromMap(data.key, value));
          }
        }
      }
    });
    return cacheObjects;
  }

  Future close() async => db.close();
}
