import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter/material.dart';

import 'package:better_player/src/configuration/better_player_data_source.dart';
import 'package:better_player/src/configuration/better_player_data_source_type.dart';
import 'package:better_player/src/video_player/no_script_tag_exception.dart';
import 'package:better_player/src/shims/dart_ui.dart' as ui;
import 'package:better_player/src/configuration/better_player_buffering_configuration.dart';
import 'package:better_player/src/video_player/video_player_platform_interface.dart';

import 'hls.dart';

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = {
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = {
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

class VideoPlayerPlugin extends VideoPlayerPlatform {
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = VideoPlayerPlugin();
  }

  Map<int, _VideoPlayer> _videoPlayers = <int, _VideoPlayer>{};

  int _textureCounter = 1;

  Map<String, String> headers = {};

  @override
  Future<void> init() async {
    _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int? textureId) async {
    if (textureId != null) {
      _videoPlayers[textureId]!.dispose();
      _videoPlayers.remove(textureId);
    }
  }

  void _disposeAllPlayers() {
    _videoPlayers.values
        .forEach((_VideoPlayer videoPlayer) => videoPlayer.dispose());
    _videoPlayers.clear();
  }

  @override
  Future<int?> create(
      {BetterPlayerBufferingConfiguration? bufferingConfiguration,
      BetterPlayerDataSource? dataSource}) async {
    final int textureId = _textureCounter;
    _textureCounter++;

    late final String url;

    if (dataSource != null) {
      switch (dataSource.type) {
        case BetterPlayerDataSourceType.network:
          url = dataSource.url;
          if (dataSource.headers != null) {
            headers = dataSource.headers!;
          }
          break;
        case BetterPlayerDataSourceType.memory:
          return Future.error(UnimplementedError(
              'web implementation of video_player cannot play local files'));
        case BetterPlayerDataSourceType.file:
          return Future.error(UnimplementedError(
              'web implementation of video_player cannot play local files'));
      }

      _videoPlayers[textureId] =
          _VideoPlayer(uri: url, textureId: textureId, headers: headers);

      _videoPlayers[textureId]!.initialize();
    }
    return textureId;
  }

  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {}

  @override
  Future<void> setLooping(int? textureId, bool looping) async {
    _videoPlayers[textureId]!.setLooping(looping);
  }

  @override
  Future<void> play(int? textureId) async {
    _videoPlayers[textureId]!.play();
  }

  @override
  Future<void> pause(int? textureId) async {
    _videoPlayers[textureId]!.pause();
  }

  @override
  Future<void> setVolume(int? textureId, double volume) async {
    _videoPlayers[textureId]!.setVolume(volume);
  }

  @override
  Future<void> setSpeed(int? textureId, double speed) async {
    assert(speed > 0);

    _videoPlayers[textureId]!.setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    _videoPlayers[textureId]!.seekTo(position ?? Duration());
  }

  @override
  Future<Duration> getPosition(int? textureId) async {
    _videoPlayers[textureId]!.sendBufferingUpdate();
    return _videoPlayers[textureId]!.getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) {
    return _videoPlayers[textureId]!.eventController.stream;
  }

  @override
  Future<bool?> isPictureInPictureEnabled(int? textureId) async {
    return false;
  }

  Future<DateTime?> getAbsolutePosition(int? textureId) async {
    final int milliseconds =
        _videoPlayers[textureId]!.getPosition().inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  @override
  Future<void> setTrackParameters(int? textureId, int? width, int? height,
      int? bitrate, int? trackId) async {
    if (trackId != null) {
      _videoPlayers[textureId]!.setTrackParameters(trackId);
    }
  }

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) =>
      Future<void>.value();

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? id) async {
    if (id != null) {
      _videoPlayers[textureId]!.setAudioTrack(id);
    }
  }

  @override
  Widget buildView(int? textureId) {
    return HtmlElementView(viewType: 'videoPlayer-$textureId');
  }
}

class _VideoPlayer {
  _VideoPlayer(
      {required this.uri, required this.textureId, required this.headers});

  final StreamController<VideoEvent> eventController =
      StreamController<VideoEvent>();

  final String uri;
  final int textureId;
  final Map<String, String> headers;

  late VideoElement videoElement;
  bool isInitialized = false;
  bool isBuffering = false;
  Hls? _hls;

  void setBuffering(bool buffering) {
    if (isBuffering != buffering) {
      isBuffering = buffering;
      eventController.add(VideoEvent(
          key: '',
          eventType: isBuffering
              ? VideoEventType.bufferingStart
              : VideoEventType.bufferingEnd));
    }
  }

  void initialize() {
    videoElement = VideoElement()
      ..src = uri
      ..autoplay = false
      ..controls = false
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%';

    // Allows Safari iOS to play the video inline
    videoElement.setAttribute('playsinline', 'true');

    ui.platformViewRegistry.registerViewFactory(
        'videoPlayer-$textureId', (int viewId) => videoElement);

    if (isSupported() && uri.contains("m3u8")) {
      try {
        _hls = Hls(
          HlsConfig(
            xhrSetup: allowInterop(
              (HttpRequest xhr, dynamic url) {
                if (headers.length == 0) return;

                if (headers.containsKey("useCookies")) {
                  xhr.withCredentials = true;
                  headers.remove("useCookies");
                }
                headers.forEach((key, value) {
                  xhr.setRequestHeader(key, value);
                });
              },
            ),
          ),
        );
        _hls!.subtitleDisplay = false;
        _hls!.on('hlsMediaAttached', allowInterop((dynamic _, dynamic __) {
          _hls!.loadSource(uri);
        }));
        _hls!.attachMedia(videoElement);
        _hls!.on('hlsError', allowInterop((dynamic _, dynamic data) {
          eventController.addError(PlatformException(
            code: _kErrorValueToErrorName[2]!,
            message: _kDefaultErrorMessage,
            details: _kErrorValueToErrorDescription[5],
          ));
        }));
        videoElement.onCanPlay.listen((dynamic _) {
          if (!isInitialized) {
            isInitialized = true;
            sendInitialized();
          }
          setBuffering(false);
        });
      } catch (e) {
        print(e);
        throw NoScriptTagException();
      }
    } else {
      videoElement.src = uri;
      videoElement.addEventListener('loadedmetadata', (_) {
        if (!isInitialized) {
          isInitialized = true;
          sendInitialized();
        }
        setBuffering(false);
      });
    }

    videoElement.onCanPlayThrough.listen((dynamic _) {
      setBuffering(false);
    });

    videoElement.onPlaying.listen((dynamic _) {
      setBuffering(false);
    });

    videoElement.onWaiting.listen((dynamic _) {
      setBuffering(true);
      sendBufferingUpdate();
    });

    // The error event fires when some form of error occurs while attempting to load or perform the media.
    videoElement.onError.listen((Event _) {
      setBuffering(false);
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      MediaError error = videoElement.error!;
      eventController.addError(PlatformException(
        code: _kErrorValueToErrorName[error.code]!,
        message: error.message != '' ? error.message : _kDefaultErrorMessage,
        details: _kErrorValueToErrorDescription[error.code],
      ));
    });

    videoElement.onEnded.listen((dynamic _) {
      setBuffering(false);
      eventController
          .add(VideoEvent(key: '', eventType: VideoEventType.completed));
    });
  }

  void sendBufferingUpdate() {
    eventController.add(VideoEvent(
      key: '',
      buffered: _toDurationRange(videoElement.buffered),
      eventType: VideoEventType.bufferingUpdate,
    ));
  }

  Future<void> play() {
    return videoElement.play().catchError((dynamic e) {
      // play() attempts to begin playback of the media. It returns
      // a Promise which can get rejected in case of failure to begin
      // playback for any reason, such as permission issues.
      // The rejection handler is called with a DomException.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
      DomException exception = e;
      eventController.addError(PlatformException(
        code: exception.name,
        message: exception.message,
      ));
    }, test: (e) => e is DomException);
  }

  void pause() => videoElement.pause();

  void setLooping(bool value) => videoElement.loop = value;

  void setAudioTrack(int id) => _hls!.audioTrack = id;

  void setTrackParameters(int trackId) => _hls!.loadLevel = trackId;

  void setVolume(double value) {
    if (value > 0.0) {
      videoElement.muted = false;
    } else {
      videoElement.muted = true;
    }
    videoElement.volume = value;
  }

  void setPlaybackSpeed(double speed) {
    assert(speed > 0);

    videoElement.playbackRate = speed;
  }

  void seekTo(Duration position) =>
      videoElement.currentTime = position.inMilliseconds.toDouble() / 1000;

  Duration getPosition() =>
      Duration(milliseconds: (videoElement.currentTime * 1000).round());

  void sendInitialized() {
    eventController.add(
      VideoEvent(
        key: '',
        eventType: VideoEventType.initialized,
        duration: Duration(
          milliseconds: (videoElement.duration * 1000).round(),
        ),
        size: Size(
          videoElement.videoWidth.toDouble(),
          videoElement.videoHeight.toDouble(),
        ),
      ),
    );
  }

  void dispose() {
    videoElement.removeAttribute('src');
    videoElement.load();
  }

  List<DurationRange> _toDurationRange(TimeRanges buffered) {
    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(milliseconds: (buffered.start(i) * 1000).round()),
        Duration(milliseconds: (buffered.end(i) * 1000).round()),
      ));
    }
    return durationRange;
  }
}
