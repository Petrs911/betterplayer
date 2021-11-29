@JS()
library hls.js;

import 'dart:html';

import 'package:js/js.dart';

@JS("Hls.isSupported")
external bool isSupported();

@JS()
class Hls {
  external factory Hls(HlsConfig config);

  @JS()
  external void stopLoad();

  @JS()
  external void loadSource(String videoSrc);

  @JS()
  external void attachMedia(VideoElement video);

  @JS()
  external set subtitleDisplay(bool enableSubtitle);

  @JS()
  external set audioTrack(int id);

  @JS()
  external set loadLevel(int id);

  @JS()
  external dynamic on(String event, Function callback);

  external HlsConfig config;
}

@JS()
@anonymous
class HlsConfig {
  @JS()
  external Function get xhrSetup;

  external factory HlsConfig({Function xhrSetup});
}
