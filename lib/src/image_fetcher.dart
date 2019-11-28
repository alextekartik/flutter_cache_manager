import 'package:flutter_cache_manager/src/file_fetcher.dart';

import 'image_fetcher_io.dart' if (dart.library.html) 'image_fetcher_web.dart'
    as impl;

FileFetcher get imageFetcher => impl.imageFetcher;
