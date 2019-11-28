import 'dart:async';
import 'dart:html';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

ImageElement createImageElement() {
  var element = ImageElement();
  element.setAttribute('crossorigin', 'anonymous');
  return element;
}

Future<ImageElement> loadImageElement(String src) async {
  ImageElement imageElement;

  var completer = Completer();
  imageElement = createImageElement();
  StreamSubscription errorSubscription;
  StreamSubscription loadSubscription;

  void _cancel() {
    loadSubscription?.cancel();
    loadSubscription = null;
    errorSubscription?.cancel();
    errorSubscription = null;
  }

  errorSubscription = imageElement.onError.listen((error) {
    print('failed ${url.basename(src)} to load $src error $error');
    _cancel();

    completer.completeError(error);
  });

  loadSubscription = imageElement.onLoad.listen((_) async {
    print('Can show $src');
    _cancel();

    /*
        if (app.imageReadyDelay != null) {
          await sleep(app.imageReadyDelay);
          print('Waited ${app.imageReadyDelay} ms for $media');
        }
         */

    completer.complete();
  });
  imageElement.src = src;
  print('loading $src');
  try {
    await completer.future;
  } finally {
    _cancel();
  }

  return imageElement;
}

FileFetcher get imageFetcher =>
    (String url, {Map<String, String> headers}) async {
      var imageElement = await loadImageElement(url);
      var dataUrl = imageElementToDataUrl(imageElement);
      final response = ImageFetcherResponse(200, utf8.encode(dataUrl));
      return response;
    };

CanvasRenderingContext2D getCanvasContext(CanvasElement element) {
  final context = element.getContext('2d') as CanvasRenderingContext2D;
  return context;
}

String imageElementToDataUrl(ImageElement element) {
  var canvas = CanvasElement(width: element.width, height: element.height);
  var context = getCanvasContext(canvas);
  context.drawImage(element, 0, 0);
/*
var dataUrl = canvas.toDataUrl();
if (dev) {
print('default data url: ${dataUrl.length} bytes');
print('[data]: ${stringSubString(dataUrl, 32)}');
}

 */
  var dataUrl = canvas.toDataUrl("image/jpeg", 75);
  return dataUrl;
}

class ImageFetcherResponse implements FileFetcherResponse {
  ImageFetcherResponse(this.statusCode, bodyBytes);

  @override
  bool hasHeader(String name) {
    return false;
  }

  @override
  String header(String name) {
    return null;
  }

  @override
  Uint8List bodyBytes;

  @override
  int statusCode;
}
