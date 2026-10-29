import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState, Track;
import 'package:media_kit_video/media_kit_video.dart' as media_video;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;

import 'models/track.dart';
import 'pages/albums_page.dart';
import 'pages/artists_page.dart';
import 'pages/favorites_page.dart';
import 'pages/explore_page.dart';
import 'pages/explore_online_page.dart';
import 'pages/home_page.dart';
import 'pages/music_page.dart';
import 'pages/playlists_page.dart';
import 'widgets/middle_content_panel.dart';
import 'widgets/mini_player.dart';
import 'widgets/now_playing_panel.dart';
import 'widgets/ambient_album_background.dart';
import 'widgets/online_search_results.dart';
import 'services/artist_song_discovery_service.dart';
import 'services/explore_discovery_service.dart';
import 'services/home_discovery_service.dart';
import 'services/listening_history_service.dart';
import 'services/playlist_library_service.dart';
import 'widgets/soundneed_sidebar.dart';
import 'widgets/soundneed_svg_icon.dart';
import 'widgets/soundneed_top_bar.dart';

export 'models/track.dart';

const _bg = Color(0xFF000000);
const _panel = Color(0xFF151522);
const _raised = Color(0xFF1D1D2B);
const _cyan = Color(0xFF83E8FF);
const _muted = Color(0xFF9292A5);
const _videoBackdropShade = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0, .18, .4, .75, 1],
    colors: [
      Color(0xE6000000),
      Color(0xB0000000),
      Color(0x85000000),
      Color(0xE8000000),
      Colors.black,
    ],
  ),
);
const _youtubeAndroidUserAgent =
    'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0 Mobile Safari/537.36';
const _windowChannel = MethodChannel('soundneed/window');
const _audioExtensions = <String>[
  'mp3',
  'flac',
  'm4a',
  'mp4',
  'wav',
  'ogg',
  'opus',
  'aac',
  'wma',
  'aiff',
  'aif',
  'ape',
];

class _ScannedTrack {
  const _ScannedTrack(this.track, this.coverBytes);
  final Track track;
  final Uint8List? coverBytes;
}

class _OnlineTrack {
  const _OnlineTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.durationSeconds,
    this.chartRank,
    this.chartKey,
    this.directAudioUrl,
  });

  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final int durationSeconds;
  final int? chartRank;
  final String? chartKey;
  final String? directAudioUrl;
}

class _HomeOnlineCategory {
  _HomeOnlineCategory(this.query);

  final String query;
  List<_OnlineTrack> tracks = const [];
  bool loading = true;
  String? error;
}

class _ResolvedOnlineAudio {
  _ResolvedOnlineAudio({
    required this.url,
    required this.contentType,
    required this.bitrate,
  }) : resolvedAt = DateTime.now();

  final String url;
  final String contentType;
  final int bitrate;
  final DateTime resolvedAt;
}

/// Matches the HTTP defaults used by the Android NewPipeDownloader so
/// YouTube sees a modern mobile client when Dart resolves and fetches streams.
class _SoundNeedYoutubeHttpClient extends YoutubeHttpClient {
  @override
  Map<String, String> get headers => {
    ...YoutubeHttpClient.defaultHeaders,
    'user-agent': _youtubeAndroidUserAgent,
    'accept': '*/*',
    'accept-encoding': 'identity',
  };
}

List<_ScannedTrack> _scanFiles(List<String> paths) {
  final tracks = <_ScannedTrack>[];
  for (final path in paths) {
    try {
      final file = File(path);
      if (!file.existsSync()) continue;
      final metadata = readMetadata(file, getImage: true);
      final fallback = path
          .split(Platform.pathSeparator)
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '');
      final title = metadata.title?.trim();
      final artist = metadata.artist?.trim();
      final cover = metadata.pictures.isEmpty
          ? null
          : metadata.pictures.first.bytes;
      tracks.add(
        _ScannedTrack(
          Track(
            path: path,
            title: title == null || title.isEmpty ? fallback : title,
            artist: artist == null || artist.isEmpty
                ? 'Artista desconocido'
                : artist,
            album: metadata.album?.trim() ?? '',
            durationMs: metadata.duration?.inMilliseconds,
          ),
          cover,
        ),
      );
    } catch (_) {
      final fallback = path
          .split(Platform.pathSeparator)
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '');
      tracks.add(
        _ScannedTrack(
          Track(path: path, title: fallback, artist: 'Artista desconocido'),
          null,
        ),
      );
    }
  }
  return tracks;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SoundNeedApp());
}

class SoundNeedApp extends StatelessWidget {
  const SoundNeedApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SoundNeed',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: _cyan,
        surface: _panel,
        onSurface: Colors.white,
        secondary: _cyan,
      ),
      fontFamily: 'Segoe UI',
      sliderTheme: SliderThemeData(
        activeTrackColor: _cyan,
        inactiveTrackColor: Colors.white.withValues(alpha: .12),
        thumbColor: _cyan,
        overlayColor: _cyan.withValues(alpha: .12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
    ),
    home: const LibraryScreen(),
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final AudioPlayer _player = AudioPlayer();
  late final Stream<bool> _audioPlayingStream = _player.playerStateStream.map(
    (state) => state.playing,
  );
  final Player _videoPlayer = Player();
  Player? _localAudioFallbackPlayer;
  Player get _localAudioFallback => _localAudioFallbackPlayer ??= Player();
  late final media_video.VideoController _videoController =
      media_video.VideoController(_videoPlayer);
  final YoutubeExplode _youtube = YoutubeExplode(
    httpClient: _SoundNeedYoutubeHttpClient(),
  );
  final TextEditingController _search = TextEditingController();
  final List<Track> _tracks = [];
  final Set<String> _favorites = {};
  final _playlistLibrary = PlaylistLibraryService.instance;
  Map<String, List<String>> get _playlists => _playlistLibrary.playlists;
  final List<String> _folders = [];
  final List<String> _queue = [];
  List<_OnlineTrack> _onlinePlaybackQueue = const [];
  final Map<String, _ResolvedOnlineAudio> _prefetchedOnlineAudio = {};
  final Map<String, Future<_ResolvedOnlineAudio?>> _onlineExtractionJobs = {};
  final Map<String, _OnlineTrack> _resolvedHomeChartTracks = {};
  int _onlineQueueIndex = -1;
  bool _onlineAdvancing = false;
  String _section = 'Inicio';
  String? _playlistView;
  int? _currentIndex;
  bool _loading = true;
  bool _scanning = false;
  bool? _sidebarCompactOverride;
  bool _exploreSidebarHovered = false;
  bool _exploreShowingTrack = false;
  ExploreDiscoveryFeed _exploreFeed = const ExploreDiscoveryFeed(
    recommendations: [],
    seeds: [],
  );
  bool _exploreRecommendationsLoading = false;
  String? _exploreRecommendationError;
  int _exploreRequestId = 0;
  bool _nowPlayingCollapsed = false;
  bool _queueOpen = false;
  bool _onlineMode = false;
  bool _loopEnabled = false;
  bool _onlineSearching = false;
  bool _onlinePlaybackLoading = false;
  bool _videoMode = false;
  bool _videoLoading = false;
  bool _videoPreviewUnavailable = true;
  String? _videoReadyTrackKey;
  bool _usingMediaKitForLocalAudio = false;
  int _videoPlaybackRequestId = 0;
  Timer? _videoAudioSyncTimer;
  bool _videoAudioSyncInProgress = false;
  bool _closing = false;
  bool _windowMaximized = Platform.isWindows;
  String? _error;
  String? _onlineError;
  _OnlineTrack? _playingOnlineTrack;
  ArtworkPalette _appPalette = ArtworkPalette.neutral;
  String? _artworkPaletteKey;
  int _artworkPaletteRequest = 0;
  String _query = '';
  List<_OnlineTrack> _onlineResults = const [];
  final _HomeOnlineCategory _colombiaChart = _HomeOnlineCategory(
    'Top Colombia 2026 canciones más escuchadas',
  );
  final _HomeOnlineCategory _worldChart = _HomeOnlineCategory(
    'Top global 2026 canciones más escuchadas',
  );
  final _HomeOnlineCategory _discoverMusic = _HomeOnlineCategory(
    'Nuevos lanzamientos música latina 2026',
  );
  List<HomeChartTrack> _colombiaTop = const [];
  List<HomeChartTrack> _worldTop = const [];
  List<HomeChartArtist> _worldArtists = const [];
  List<String> _preferredArtists = const [];
  Set<String> _recentlyHeardTrackKeys = const {};
  Map<String, int> _trackPlayCounts = const {};
  String? _resolvingChartKey;
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  Duration? _duration;
  double _volume = .78;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  StreamSubscription<Duration>? _localAudioPositionSubscription;
  StreamSubscription<Duration>? _localAudioDurationSubscription;
  StreamSubscription<Playlist>? _localAudioPlaylistSubscription;
  Timer? _pruneTimer;
  Timer? _onlineDebounce;
  Timer? _exploreMeterTimer;
  bool _exploreMeterRequestPending = false;
  List<double> _exploreSpectrum = List<double>.filled(32, 0);
  int _onlineRequestId = 0;
  int _onlinePlaybackRequestId = 0;
  int _listeningSessionId = 0;
  int _recordedListeningSessionId = -1;

  @override
  void initState() {
    super.initState();
    // Pre-initialize video player to avoid first-time loading issues
    unawaited(_videoPlayer.open(Media(''), play: false).catchError((_) {}));
    _restore();
    unawaited(_loadListeningHistory());
    unawaited(_loadHomeChart(_colombiaChart, colombia: true));
    unawaited(_loadHomeChart(_worldChart, colombia: false));
    unawaited(_loadHomeCategory(_discoverMusic));
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!mounted || _usingMediaKitForLocalAudio) return;
      if (index != null && index != _currentIndex) _beginListeningSession();
      setState(() {
        _currentIndex = index;
        _duration = _player.duration;
      });
      unawaited(_updateArtworkPalette());
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted && !_usingMediaKitForLocalAudio) {
        setState(() => _duration = duration);
      }
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (!_usingMediaKitForLocalAudio) {
        _position.value = position;
        _maybeRecordListeningAtHalfway(position, _duration ?? _player.duration);
      }
    });
    _errorSubscription = _player.errorStream.listen((error) {
      if (_usingMediaKitForLocalAudio) return;
      final online = _playingOnlineTrack != null;
      unawaited(
        _writePlaybackLog('Player error code=${error.code}: ${error.message}'),
      );
      if (mounted) {
        setState(() {
          _error =
              '${online ? 'Audio online' : 'Reproducción'} (${error.code}): ${error.message}';
          if (online) _onlinePlaybackLoading = false;
        });
      }
    });
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _playingOnlineTrack != null) {
        unawaited(_skipOnlineTrack(1));
      }
    });
  }

  Future<void> _toggleWindowMaximize() async {
    final maximized = await _windowChannel.invokeMethod<bool>('toggleMaximize');
    if (mounted && maximized != null) {
      setState(() => _windowMaximized = maximized);
    }
  }

  void _navigate(String label) {
    final reloadExplore =
        label == 'Explorar' && (_section != 'Explorar' || _exploreShowingTrack);
    setState(() {
      if (label == 'Explorar') {
        _exploreSidebarHovered = false;
        _exploreShowingTrack = false;
      }
      if (_playlists.containsKey(label)) {
        _section = 'Playlists';
        _playlistView = label;
      } else {
        _section = label;
        _playlistView = null;
      }
    });
    _exploreMeterTimer?.cancel();
    _exploreMeterTimer = null;
    _exploreSpectrum = List<double>.filled(32, 0);
    unawaited(
      _windowChannel
          .invokeMethod<void>('stopOutputSpectrum')
          .catchError((_) {}),
    );
    if (reloadExplore) unawaited(_loadExploreRecommendations());
  }

  void _returnToExploreDiscoveries() {
    setState(() => _exploreShowingTrack = false);
    unawaited(_loadExploreRecommendations());
  }

  void _openCurrentTrackInExplore() {
    setState(() {
      _section = 'Explorar';
      _playlistView = null;
      _exploreSidebarHovered = false;
      _exploreShowingTrack = true;
    });
    _startExploreSpectrumPolling();
    unawaited(_loadExploreRecommendations());
  }

  void _startExploreSpectrumPolling() {
    _exploreMeterTimer?.cancel();
    if (!Platform.isWindows) return;
    _exploreSpectrum = List<double>.filled(32, 0);
    unawaited(
      _windowChannel
          .invokeMethod<void>('startOutputSpectrum')
          .catchError((_) {}),
    );
    _exploreMeterTimer = Timer.periodic(const Duration(milliseconds: 55), (
      _,
    ) async {
      if (!mounted || _section != 'Explorar' || _exploreMeterRequestPending) {
        return;
      }
      _exploreMeterRequestPending = true;
      try {
        final values = await _windowChannel.invokeListMethod<double>(
          'getOutputSpectrum',
        );
        if (mounted &&
            values != null &&
            values.length == 32 &&
            _section == 'Explorar') {
          final nextSpectrum = values
              .map((value) => value.clamp(0.0, 1.0).toDouble())
              .toList(growable: false);
          var changed = false;
          for (var i = 0; i < nextSpectrum.length; i++) {
            if ((nextSpectrum[i] - _exploreSpectrum[i]).abs() >= .01) {
              changed = true;
              break;
            }
          }
          if (changed) {
            setState(() => _exploreSpectrum = nextSpectrum);
          }
        }
      } catch (_) {
        // The visualizer stays still if output capture is unavailable.
      } finally {
        _exploreMeterRequestPending = false;
      }
    });
  }

  Future<void> _loadExploreRecommendations({bool refresh = false}) async {
    final requestId = ++_exploreRequestId;
    if (mounted) {
      setState(() {
        _exploreRecommendationsLoading = true;
        _exploreRecommendationError = null;
        _exploreFeed = const ExploreDiscoveryFeed(
          recommendations: [],
          seeds: [],
        );
      });
    }
    try {
      final profile = await ListeningHistoryService.instance.load();
      final feed = await ExploreDiscoveryService.instance.discover(
        history: profile,
        youtube: _youtube,
        favoriteArtists: _tracks
            .where((track) => _favorites.contains(track.path))
            .map((track) => track.artist),
        refresh: refresh,
      );
      if (!mounted || requestId != _exploreRequestId) return;
      setState(() {
        _preferredArtists = profile.preferredArtists;
        _recentlyHeardTrackKeys = profile.recentTrackKeys;
        _trackPlayCounts = profile.trackPlayCounts;
        _exploreFeed = feed;
        _exploreRecommendationsLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _exploreRequestId) return;
      setState(() {
        _exploreRecommendationError =
            'No se pudieron cargar artistas relacionados. Revisa tu conexión.';
        _exploreRecommendationsLoading = false;
      });
    }
  }

  Future<void> _playExploreRecommendation(
    ExploreRecommendation recommendation,
  ) async {
    setState(() => _exploreShowingTrack = true);
    _startExploreSpectrumPolling();
    try {
      // A one-song queue must never loop back to the same recommendation while
      // the rest of the related queue is still being resolved.
      if (_loopEnabled) await _player.setLoopMode(LoopMode.off);
      final selected = await _resolveExploreRecommendation(recommendation);
      if (selected == null) {
        if (mounted)
          _toast('No encontramos una versión online para reproducir.');
        return;
      }
      final selectedTitle = _normalizeChartText(recommendation.title);
      final nextRecommendations = _exploreFeed.recommendations
          .where(
            (item) =>
                item.id != recommendation.id &&
                _normalizeChartText(item.title) != selectedTitle,
          )
          .take(5)
          .toList(growable: false);
      await _playOnlineTrack(selected, queue: [selected], queueIndex: 0);
      final requestId = _onlinePlaybackRequestId;
      unawaited(
        _extendExploreRecommendationQueue(
          selected,
          nextRecommendations,
          requestId,
        ),
      );
    } catch (_) {
      if (mounted) _toast('No se pudo resolver esta canción online.');
    }
  }

  Future<_OnlineTrack?> _resolveExploreRecommendation(
    ExploreRecommendation recommendation,
  ) async {
    final videoId = recommendation.videoId;
    if (videoId != null) {
      return _OnlineTrack(
        videoId: videoId,
        title: recommendation.title,
        artist: recommendation.artist,
        thumbnail: recommendation.artworkUrl,
        durationSeconds: 0,
      );
    }
    final videos = await _youtube.search
        .search('${recommendation.title} ${recommendation.artist} audio')
        .timeout(const Duration(seconds: 15));
    final candidates = videos
        .take(12)
        .map(
          (video) => _OnlineTrack(
            videoId: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnail: recommendation.artworkUrl.isEmpty
                ? video.thumbnails.highResUrl
                : recommendation.artworkUrl,
            durationSeconds: video.duration?.inSeconds ?? 0,
          ),
        )
        .where(
          (track) =>
              RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(track.videoId) &&
              track.title.isNotEmpty,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final titleKey = _normalizeChartText(recommendation.title);
    final artistKey = _normalizeChartText(recommendation.artist);
    candidates.sort((a, b) {
      int matchScore(_OnlineTrack track) {
        final title = _normalizeChartText(track.title);
        final artist = _normalizeChartText(track.artist);
        return (title.contains(titleKey) ? 3 : 0) +
            (artist.contains(artistKey) || title.contains(artistKey) ? 2 : 0) +
            (track.durationSeconds >= 90 ? 1 : 0);
      }

      return matchScore(b).compareTo(matchScore(a));
    });
    return candidates.first;
  }

  Future<void> _extendExploreRecommendationQueue(
    _OnlineTrack selected,
    List<ExploreRecommendation> recommendations,
    int requestId,
  ) async {
    if (recommendations.isEmpty) return;
    final resolved = await Future.wait(
      recommendations.map(_resolveExploreRecommendation),
    );
    final queue = <_OnlineTrack>[selected];
    final seenIds = <String>{selected.videoId};
    final seenTitles = <String>{_normalizeChartText(selected.title)};
    for (final track in resolved) {
      if (track == null || !seenIds.add(track.videoId)) continue;
      final title = _normalizeChartText(track.title);
      if (title.isEmpty || !seenTitles.add(title)) continue;
      queue.add(track);
    }
    if (!mounted ||
        requestId != _onlinePlaybackRequestId ||
        _playingOnlineTrack?.videoId != selected.videoId) {
      return;
    }
    setState(() {
      _onlinePlaybackQueue = queue;
      _onlineQueueIndex = 0;
    });
    if (_loopEnabled) {
      if (queue.length > 1) {
        await _player.setLoopMode(LoopMode.all);
      } else {
        await _player.setLoopMode(LoopMode.off);
        if (mounted) setState(() => _loopEnabled = false);
      }
    }
    if (_player.processingState == ProcessingState.completed &&
        queue.length > 1) {
      unawaited(_skipOnlineTrack(1));
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawTracks = prefs.getString('library.v1');
      if (rawTracks != null) {
        final decoded = jsonDecode(rawTracks) as List<dynamic>;
        _tracks.addAll(
          decoded.map((item) => Track.fromJson(item as Map<String, dynamic>)),
        );
      }
      _favorites.addAll(prefs.getStringList('favorites.v1') ?? []);
      _folders.addAll(prefs.getStringList('folders.v1') ?? []);
      _playlistLibrary.restore(
        prefs.getString(PlaylistLibraryService.storageKey),
      );
      final lastPath = prefs.getString('lastTrack.v1');
      if (lastPath != null) {
        final index = _tracks.indexWhere((track) => track.path == lastPath);
        if (index >= 0 && File(lastPath).existsSync())
          await _loadQueue(_tracks, startAt: index, autoplay: false);
      }
      await _pruneMissingTracks();
    } catch (error) {
      _error = 'No se pudo recuperar la biblioteca: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'library.v1',
      jsonEncode(_tracks.map((track) => track.toJson()).toList()),
    );
  }

  Future<void> _pruneMissingTracks() async {
    final gone = _tracks
        .where((track) => !File(track.path).existsSync())
        .map((track) => track.path)
        .toSet();
    if (gone.isEmpty) return;
    _tracks.removeWhere((track) => gone.contains(track.path));
    _favorites.removeAll(gone);
    await _playlistLibrary.removeMissingTracks(gone);
    _folders.removeWhere((path) => !Directory(path).existsSync());
    await _saveLibrary();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites.v1', _favorites.toList());
    await prefs.setStringList('folders.v1', _folders);
  }

  Future<void> _importFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Audio', extensions: _audioExtensions),
      ],
    );
    if (files.isNotEmpty)
      await _indexPaths(files.map((file) => file.path).toList());
  }

  Future<void> _importFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Importar esta carpeta',
    );
    if (path == null) return;
    if (!_folders.contains(path)) {
      _folders.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('folders.v1', _folders);
    }
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      final paths = <String>[];
      await for (final entity in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File &&
            _audioExtensions.any(
              (ext) => entity.path.toLowerCase().endsWith('.$ext'),
            )) {
          paths.add(entity.path);
        }
      }
      await _indexPaths(paths, alreadyScanning: true);
    } catch (error) {
      if (mounted)
        setState(() => _error = 'No se pudo leer la carpeta: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _indexPaths(
    List<String> paths, {
    bool alreadyScanning = false,
  }) async {
    final known = _tracks.map((track) => track.path.toLowerCase()).toSet();
    final unique = paths
        .where((path) => !known.contains(path.toLowerCase()))
        .toSet()
        .toList();
    if (unique.isEmpty) {
      if (mounted) _toast('Esos archivos ya están en tu biblioteca.');
      return;
    }
    if (mounted && !alreadyScanning) setState(() => _scanning = true);
    try {
      final scanned = await compute(
        _scanFiles,
        unique,
        debugLabel: 'scan audio metadata',
      );
      final support = await getApplicationSupportDirectory();
      final covers = Directory(
        '${support.path}${Platform.pathSeparator}covers',
      );
      await covers.create(recursive: true);
      for (final item in scanned) {
        var track = item.track;
        final bytes = item.coverBytes;
        if (bytes != null && bytes.isNotEmpty) {
          final name =
              '${sha1.convert(utf8.encode(track.path.toLowerCase()))}.img';
          final coverFile = File(
            '${covers.path}${Platform.pathSeparator}$name',
          );
          if (!await coverFile.exists())
            await coverFile.writeAsBytes(bytes, flush: true);
          track = Track(
            path: track.path,
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationMs: track.durationMs,
            coverPath: coverFile.path,
          );
        }
        _tracks.add(track);
      }
      await _saveLibrary();
      if (mounted) setState(() {});
      if (_currentIndex == null && _tracks.isNotEmpty)
        await _loadQueue(_tracks, startAt: _tracks.length - scanned.length);
      if (mounted) _toast('Se añadieron ${scanned.length} canciones.');
    } catch (error) {
      if (mounted)
        setState(
          () => _error = 'No se pudieron importar algunos archivos: $error',
        );
    } finally {
      if (mounted && !alreadyScanning) setState(() => _scanning = false);
    }
  }

  List<Track> _cachedVisibleTracks = [];
  String? _cachedSection;
  String? _cachedPlaylistView;
  String? _cachedQuery;
  Set<String>? _cachedFavorites;
  Map<String, List<String>>? _cachedPlaylists;

  List<Track> get _visibleTracks {
    // Check if cache is valid
    if (_cachedSection == _section &&
        _cachedPlaylistView == _playlistView &&
        _cachedQuery == _query &&
        _cachedFavorites == _favorites &&
        _cachedPlaylists == _playlists) {
      return _cachedVisibleTracks;
    }

    // Recalculate and cache
    Iterable<Track> view = _tracks;
    if (_section == 'Favoritos')
      view = view.where((track) => _favorites.contains(track.path));
    if (_section == 'Playlists' && _playlistView != null) {
      final paths = _playlists[_playlistView] ?? const <String>[];
      view = view.where((track) => paths.contains(track.path));
    }
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty)
      view = view.where(
        (track) =>
            track.title.toLowerCase().contains(query) ||
            track.artist.toLowerCase().contains(query) ||
            track.album.toLowerCase().contains(query),
      );

    _cachedVisibleTracks = view.toList();
    _cachedSection = _section;
    _cachedPlaylistView = _playlistView;
    _cachedQuery = _query;
    _cachedFavorites = Set.from(_favorites);
    _cachedPlaylists = Map.from(_playlists);

    return _cachedVisibleTracks;
  }

  Future<void> _updateArtworkPalette() async {
    final online = _playingOnlineTrack;
    final local = online == null ? _currentLocalTrack : null;
    final coverPath = local?.coverPath;
    final key = online != null
        ? 'online:${online.videoId}:${online.thumbnail}'
        : local == null
        ? null
        : 'local:${local.path}:${coverPath ?? ''}';
    if (key == _artworkPaletteKey) return;
    _artworkPaletteKey = key;
    final request = ++_artworkPaletteRequest;
    if (key == null ||
        (online == null && (coverPath == null || coverPath.isEmpty))) {
      if (mounted && _appPalette != ArtworkPalette.neutral) {
        setState(() => _appPalette = ArtworkPalette.neutral);
      }
      return;
    }

    try {
      Uint8List bytes;
      if (online != null) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 7);
        try {
          final response = await client
              .getUrl(Uri.parse(online.thumbnail))
              .then((request) => request.close())
              .timeout(const Duration(seconds: 9));
          if (response.statusCode < 200 || response.statusCode >= 300) return;
          bytes = await consolidateHttpClientResponseBytes(response)
              .timeout(const Duration(seconds: 9));
        } finally {
          client.close(force: true);
        }
      } else {
        bytes = await File(coverPath!).readAsBytes();
      }
      final palette = await ArtworkPaletteExtractor.fromBytes(bytes);
      if (mounted && request == _artworkPaletteRequest) {
        setState(() => _appPalette = palette);
      }
    } catch (_) {
      if (mounted && request == _artworkPaletteRequest) {
        setState(() => _appPalette = ArtworkPalette.neutral);
      }
    }
  }

  Track? get _currentLocalTrack {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return null;
    final path = _queue[index];
    for (final track in _tracks) {
      if (track.path == path) return track;
    }
    return null;
  }

  Future<void> _loadQueue(
    List<Track> tracks, {
    int startAt = 0,
    bool autoplay = true,
  }) async {
    if (tracks.isEmpty) return;
    final requestedIndex = startAt.clamp(0, tracks.length - 1).toInt();
    final requestedPath = tracks[requestedIndex].path;
    final availableTracks = <Track>[];
    final missingPaths = <String>{};
    for (final track in tracks) {
      if (await File(track.path).exists()) {
        availableTracks.add(track);
      } else {
        missingPaths.add(track.path);
      }
    }
    if (missingPaths.isNotEmpty) {
      if (mounted) {
        _toast(
          'Se omitieron ${missingPaths.length} canciones porque sus archivos no están disponibles ahora.',
        );
      }
    }
    if (availableTracks.isEmpty) {
      if (mounted) {
        setState(() {
          _error =
              'No quedan archivos disponibles para reproducir en esta cola.';
        });
      }
      return;
    }
    var queueStartAt = availableTracks.indexWhere(
      (track) => track.path == requestedPath,
    );
    if (queueStartAt < 0) {
      final nextAvailablePath = tracks
          .skip(requestedIndex + 1)
          .map((track) => track.path)
          .where((path) => availableTracks.any((track) => track.path == path))
          .firstOrNull;
      queueStartAt = nextAvailablePath == null
          ? 0
          : availableTracks.indexWhere(
              (track) => track.path == nextAvailablePath,
            );
    }
    if (_usingMediaKitForLocalAudio) {
      await _localAudioFallback.stop();
      _usingMediaKitForLocalAudio = false;
    }
    final keepVideoMode = _videoMode;
    if (keepVideoMode) {
      _videoPlaybackRequestId++;
      _videoAudioSyncTimer?.cancel();
      await _videoPlayer.stop();
    }
    _onlinePlaybackRequestId++;
    _playingOnlineTrack = null;
    _onlinePlaybackLoading = false;
    _onlinePlaybackQueue = const [];
    _onlineQueueIndex = -1;
    _error = null;
    _beginListeningSession();
    try {
      await _startLocalAudioPlayback(
        availableTracks,
        queueStartAt,
        autoplay: autoplay,
        keepVideoMode: keepVideoMode,
      );
    } catch (error) {
      final failedTrack = availableTracks[queueStartAt];
      final stillExists = await File(failedTrack.path).exists();
      if (mounted) {
        setState(
          () => _error = stillExists
              ? 'No se pudo reproducir "${failedTrack.title}" con el reproductor local. Comprueba que el formato sea compatible. Ruta: ${failedTrack.path}. Error: $error'
              : 'No se encuentra el archivo de "${failedTrack.title}". Comprueba que la unidad o carpeta siga conectada. Ruta: ${failedTrack.path}. Error: $error',
        );
      }
    }
  }

  Future<void> _startLocalAudioPlayback(
    List<Track> tracks,
    int startAt, {
    required bool autoplay,
    required bool keepVideoMode,
  }) async {
    await _player.stop();
    await _localAudioFallback.setVolume(_volume * 100);
    await _localAudioFallback.setShuffle(_player.shuffleModeEnabled);
    await _localAudioFallback.setPlaylistMode(
      _loopEnabled ? PlaylistMode.loop : PlaylistMode.none,
    );
    _listenToLocalAudioFallback();
    _usingMediaKitForLocalAudio = true;
    try {
      await _localAudioFallback.open(
        Playlist(
          List.generate(
            tracks.length,
            (index) => Media(Uri.file(tracks[index].path).toString()),
            growable: false,
          ),
          index: startAt,
        ),
        play: autoplay,
      );
    } catch (_) {
      _usingMediaKitForLocalAudio = false;
      rethrow;
    }
    _queue
      ..clear()
      ..addAll(tracks.map((track) => track.path));
    _currentIndex = startAt;
    unawaited(_updateArtworkPalette());
    _position.value = _localAudioFallback.state.position;
    _duration = _localAudioFallback.state.duration;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastTrack.v1', tracks[startAt].path);
    if (mounted) {
      setState(() {
        _onlinePlaybackLoading = false;
        _error = null;
      });
    }
    if (keepVideoMode && autoplay && mounted) {
      unawaited(_playVideoPreview(tracks[startAt], null));
    }
  }

  void _listenToLocalAudioFallback() {
    if (_localAudioPositionSubscription != null) return;
    _localAudioPositionSubscription = _localAudioFallback.stream.position
        .listen((position) {
          if (_usingMediaKitForLocalAudio) {
            _position.value = position;
            _maybeRecordListeningAtHalfway(
              position,
              _duration ?? _localAudioFallback.state.duration,
            );
          }
        });
    _localAudioDurationSubscription = _localAudioFallback.stream.duration
        .listen((duration) {
          if (_usingMediaKitForLocalAudio && mounted) {
            setState(() => _duration = duration);
          }
        });
    _localAudioPlaylistSubscription = _localAudioFallback.stream.playlist
        .listen((playlist) {
          if (_usingMediaKitForLocalAudio && mounted) {
            if (playlist.index != _currentIndex) _beginListeningSession();
            setState(() => _currentIndex = playlist.index);
            unawaited(_updateArtworkPalette());
          }
        });
  }

  Future<void> _loadListeningHistory() async {
    final profile = await ListeningHistoryService.instance.load();
    if (!mounted) return;
    setState(() {
      _preferredArtists = profile.preferredArtists;
      _recentlyHeardTrackKeys = profile.recentTrackKeys;
      _trackPlayCounts = profile.trackPlayCounts;
    });
  }

  Future<void> _recordListening(String title, String artist) async {
    final profile = await ListeningHistoryService.instance.record(
      title: title,
      artist: artist,
    );
    if (!mounted) return;
    setState(() {
      _preferredArtists = profile.preferredArtists;
      _recentlyHeardTrackKeys = profile.recentTrackKeys;
      _trackPlayCounts = profile.trackPlayCounts;
    });
    if (_section == 'Explorar' && _playingOnlineTrack != null) {
      unawaited(_loadExploreRecommendations());
    }
  }

  void _beginListeningSession() {
    _listeningSessionId++;
  }

  void _maybeRecordListeningAtHalfway(Duration position, Duration? duration) {
    if (duration == null ||
        duration.inMilliseconds <= 0 ||
        position.inMilliseconds < duration.inMilliseconds ~/ 2 ||
        _recordedListeningSessionId == _listeningSessionId) {
      return;
    }
    final online = _playingOnlineTrack;
    final local = online == null ? _currentLocalTrack : null;
    final title = online?.title ?? local?.title;
    final artist = online?.artist ?? local?.artist;
    if (title == null || artist == null) return;
    _recordedListeningSessionId = _listeningSessionId;
    unawaited(_recordListening(title, artist));
  }

  Future<void> _playCollection(
    List<Track> tracks,
    int startAt,
    bool shuffle,
  ) async {
    if (tracks.isEmpty) return;
    final requested = tracks[startAt.clamp(0, tracks.length - 1).toInt()];
    final onlineId = PlaylistLibraryService.onlineVideoId(requested.path);
    if (onlineId != null) {
      final onlineQueue = tracks
          .map((track) {
            final id = PlaylistLibraryService.onlineVideoId(track.path);
            final decoded = PlaylistLibraryService.decodeOnlineTrack(
              track.path,
            );
            if (id == null || decoded == null) return null;
            return _OnlineTrack(
              videoId: id,
              title: decoded.title,
              artist: decoded.artist,
              thumbnail: decoded.coverPath ?? '',
              durationSeconds: (decoded.durationMs ?? 0) ~/ 1000,
            );
          })
          .whereType<_OnlineTrack>()
          .toList(growable: false);
      final start = onlineQueue.indexWhere(
        (track) => track.videoId == onlineId,
      );
      if (onlineQueue.isNotEmpty) {
        await _playOnlineTrack(
          onlineQueue[start < 0 ? 0 : start],
          queue: onlineQueue,
          queueIndex: start < 0 ? 0 : start,
        );
        return;
      }
    }
    final localTracks = tracks
        .where(
          (track) => PlaylistLibraryService.onlineVideoId(track.path) == null,
        )
        .toList(growable: false);
    if (localTracks.isEmpty) return;
    final localStart = localTracks.indexWhere(
      (track) => track.path == requested.path,
    );
    if (shuffle) {
      final mixed = List<Track>.of(localTracks)..shuffle();
      await _loadQueue(mixed);
      return;
    }
    await _loadQueue(localTracks, startAt: localStart < 0 ? 0 : localStart);
  }

  Future<void> _playTrack(Track track) async {
    final source = _visibleTracks;
    final index = source.indexWhere((item) => item.path == track.path);
    await _loadQueue(
      source.isEmpty ? [track] : source,
      startAt: index < 0 ? 0 : index,
    );
  }

  Future<void> _playSurpriseMix() async {
    if (_tracks.isNotEmpty) {
      final mix = List<Track>.of(_tracks)..shuffle();
      await _loadQueue(mix.take(20).toList(growable: false));
      return;
    }
    if (_colombiaChart.tracks.isNotEmpty) {
      await _playOnlineTrack(
        _colombiaChart.tracks.first,
        queue: _colombiaChart.tracks,
        queueIndex: 0,
      );
      return;
    }
    if (mounted) {
      _toast('Importa canciones o espera a que cargue Top Colombia.');
    }
  }

  Future<void> _playArtistStation(String artist) async {
    try {
      final videos = await _youtube.search.search('$artist mix canciones');
      final results = videos
          .take(20)
          .map(
            (video) => _OnlineTrack(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              thumbnail: video.thumbnails.highResUrl,
              durationSeconds: video.duration?.inSeconds ?? 0,
            ),
          )
          .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
          .toList(growable: false);
      if (results.isEmpty) {
        if (mounted) _toast('No encontramos canciones de $artist.');
        return;
      }
      await _playOnlineTrack(results.first, queue: results, queueIndex: 0);
    } catch (_) {
      if (mounted) _toast('No se pudo cargar la estación de $artist.');
    }
  }

  Future<void> _playArtistDiscoveryTrack(
    ArtistSongResult track,
    List<ArtistSongResult> songs,
  ) async {
    final queue = songs
        .map(
          (song) => _OnlineTrack(
            videoId: song.videoId,
            title: song.title,
            artist: song.artist,
            thumbnail: song.artworkUrl,
            durationSeconds: song.durationSeconds,
          ),
        )
        .toList(growable: false);
    final index = queue.indexWhere((song) => song.videoId == track.videoId);
    if (index < 0) return;
    await _playOnlineTrack(queue[index], queue: queue, queueIndex: index);
  }

  Future<void> _toggleFavorite(Track track) async {
    if (!_favorites.add(track.path)) _favorites.remove(track.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites.v1', _favorites.toList());
    if (mounted) setState(() {});
  }

  Future<void> _createPlaylist() async {
    final sectionBeforeDialog = _section;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Nueva playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Nombre de la playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (!await _playlistLibrary.create(name)) {
      _toast('Ya existe una playlist con ese nombre.');
      return;
    }
    setState(() {
      if (sectionBeforeDialog == 'Playlists') {
        _section = 'Playlists';
        _playlistView = name;
      } else {
        _section = sectionBeforeDialog;
        _playlistView = null;
      }
    });
  }

  Future<void> _renamePlaylist(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Renombrar playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == currentName || !mounted) return;
    if (!await _playlistLibrary.rename(currentName, name)) {
      _toast('Ya existe una playlist con ese nombre.');
      return;
    }
    if (_playlistView == currentName) _playlistView = name;
    if (mounted) setState(() {});
  }

  Future<void> _deletePlaylist(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Eliminar playlist'),
        content: Text(
          'Se eliminará "$name". Las canciones seguirán en tu biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB9505C),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _playlistLibrary.delete(name);
    if (_playlistView == name) {
      _playlistView = null;
      _section = 'Playlists';
    }
    if (mounted) setState(() {});
  }

  Future<void> _removeFromCurrentPlaylist(String trackPath) async {
    final playlist = _playlistView;
    if (playlist == null) return;
    await _removeTrackFromPlaylist(playlist, trackPath);
  }

  Future<void> _removeTrackFromPlaylist(
    String playlist,
    String trackPath,
  ) async {
    await _playlistLibrary.removeTrack(playlist, trackPath);
    if (mounted) {
      setState(() {});
      _toast('Canción quitada de $playlist.');
    }
  }

  Future<void> _addTracksToPlaylist(String playlist, List<Track> tracks) async {
    if (!_playlists.containsKey(playlist) || tracks.isEmpty) return;
    final added = await _playlistLibrary.addTracks(
      playlist,
      tracks.map((track) => track.path),
    );
    if (mounted) {
      setState(() {});
      _toast(
        added == 1
            ? 'Se agregó 1 canción a $playlist.'
            : 'Se agregaron $added canciones a $playlist.',
      );
    }
  }

  Future<void> _addToPlaylist(Track track) async {
    if (_playlists.isEmpty) {
      _toast('Crea primero una playlist.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: _panel,
        title: const Text('Añadir a playlist'),
        children: _playlists.keys
            .map(
              (name) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, name),
                child: Text(name),
              ),
            )
            .toList(),
      ),
    );
    if (name == null) return;
    final added = await _playlistLibrary.addTracks(name, [track.path]);
    if (mounted) {
      setState(() {});
      _toast(added == 0 ? 'La canción ya está en $name.' : 'Añadida a $name.');
    }
  }

  Track _libraryTrackForOnline(_OnlineTrack track) {
    final metadata = Track(
      path: '',
      title: track.title,
      artist: track.artist,
      coverPath: track.thumbnail,
      durationMs: track.durationSeconds * 1000,
    );
    return Track(
      path: PlaylistLibraryService.encodeOnlineTrack(metadata, track.videoId),
      title: metadata.title,
      artist: metadata.artist,
      coverPath: metadata.coverPath,
      durationMs: metadata.durationMs,
    );
  }

  Future<void> _addChartTrackToPlaylist(HomeChartTrack chartTrack) async {
    final resolved = await _resolveHomeChartTrack(chartTrack, session: 'world');
    if (!mounted) return;
    if (resolved == null) {
      _toast('No pudimos identificar la versión exacta para guardarla.');
      return;
    }
    await _addToPlaylist(_libraryTrackForOnline(resolved));
  }

  Future<void> _toggleChartFavorite(HomeChartTrack chartTrack) async {
    final title = _normalizeChartText(chartTrack.title);
    final artist = _normalizeChartText(chartTrack.artist);
    final matchingKeys = _favorites
        .where((key) {
          final saved = PlaylistLibraryService.decodeOnlineTrack(key);
          return saved != null &&
              _normalizeChartText(saved.title) == title &&
              _normalizeChartText(saved.artist) == artist;
        })
        .toList(growable: false);

    if (matchingKeys.isNotEmpty) {
      _favorites.removeAll(matchingKeys);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorites.v1', _favorites.toList());
      if (mounted) {
        setState(() {});
        _toast('Quitada de Me gusta.');
      }
      return;
    }

    final resolved = await _resolveHomeChartTrack(chartTrack, session: 'world');
    if (resolved == null) {
      if (mounted) _toast('No pudimos identificar la canción para guardarla.');
      return;
    }
    _favorites.add(_libraryTrackForOnline(resolved).path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites.v1', _favorites.toList());
    if (mounted) {
      setState(() {});
      _toast('Añadida a Me gusta.');
    }
  }

  Future<void> _addOnlineToPlaylist(_OnlineTrack track) async {
    if (_playlists.isEmpty) {
      _toast('Crea primero una playlist.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: _panel,
        title: const Text('Añadir canción online a playlist'),
        children: _playlists.keys
            .map(
              (name) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, name),
                child: Text(name),
              ),
            )
            .toList(),
      ),
    );
    if (name == null) return;
    final key = PlaylistLibraryService.encodeOnlineTrack(
      Track(
        path: '',
        title: track.title,
        artist: track.artist,
        coverPath: track.thumbnail,
        durationMs: track.durationSeconds * 1000,
      ),
      track.videoId,
    );
    final added = await _playlistLibrary.addTracks(name, [key]);
    if (!mounted) return;
    setState(() {});
    _toast(added == 0 ? 'La canción ya está en $name.' : 'Añadida a $name.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _writePlaybackLog(String message) async {
    try {
      final support = await getApplicationSupportDirectory();
      final logDirectory = Directory(
        '${support.path}${Platform.pathSeparator}logs',
      );
      await logDirectory.create(recursive: true);
      final file = File(
        '${logDirectory.path}${Platform.pathSeparator}soundneed.log',
      );
      final line =
          '${DateTime.now().toIso8601String()} $message${Platform.lineTerminator}';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must not interrupt playback.
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    setState(() {
      _query = value;
      if (query.isNotEmpty) {
        _section = 'Buscar';
        _playlistView = null;
      } else if (_section == 'Buscar') {
        _section = 'Inicio';
      }
    });
    _onlineDebounce?.cancel();
    final requestId = ++_onlineRequestId;
    if (_section != 'Buscar' || query.isEmpty) {
      setState(() {
        _onlineResults = const [];
        _onlineSearching = false;
        _onlineError = null;
        _onlineMode = false;
      });
      return;
    }

    setState(() {
      _onlineResults = const [];
      _onlineSearching = true;
      _onlineError = null;
      _onlineMode = true;
    });
    _onlineDebounce = Timer(
      const Duration(milliseconds: 650),
      () => _searchOnline(query, requestId),
    );
  }

  Future<void> _searchOnline(String query, int requestId) async {
    try {
      final videos = await _youtube.search.search(query.trim());
      final results = videos
          .take(30)
          .map(
            (video) => _OnlineTrack(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              thumbnail: video.thumbnails.highResUrl,
              durationSeconds: video.duration?.inSeconds ?? 0,
            ),
          )
          .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
          .toList();
      if (!mounted || requestId != _onlineRequestId) return;
      setState(() {
        _onlineResults = results;
        _onlineSearching = false;
        _onlineError = results.isEmpty
            ? 'No encontramos resultados. Prueba con otra búsqueda.'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _onlineRequestId) return;
      setState(() {
        _onlineResults = const [];
        _onlineSearching = false;
        _onlineError = 'No se pudo completar la búsqueda. Comprueba tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _loadHomeCategory(
    _HomeOnlineCategory category, {
    bool refresh = false,
  }) async {
    if (category.loading && category.tracks.isNotEmpty && !refresh) return;
    setState(() {
      category.loading = true;
      category.error = null;
    });

    try {
      final videos = await _youtube.search.search(category.query);
      final tracks = videos
          .take(12)
          .map(
            (video) => _OnlineTrack(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              thumbnail: video.thumbnails.highResUrl,
              durationSeconds: video.duration?.inSeconds ?? 0,
            ),
          )
          .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        category.tracks = tracks;
        category.loading = false;
        category.error = tracks.isEmpty
            ? 'No encontramos resultados para esta sección.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        category.loading = false;
        category.error = 'No se pudo cargar esta sección. Revisa tu conexión.';
      });
    }
  }

  Future<void> _loadHomeChart(
    _HomeOnlineCategory category, {
    required bool colombia,
    bool refresh = false,
  }) async {
    if (mounted) {
      setState(() {
        category.loading = true;
        category.error = null;
      });
    }
    try {
      final chart = colombia
          ? await HomeChartsService.instance.loadColombia(refresh: refresh)
          : await HomeChartsService.instance.loadWorld(refresh: refresh);
      final artistTrends = colombia
          ? null
          : await HomeChartsService.instance.rankWorldArtists(chart);
      if (!mounted) return;
      final visibleChart = chart.take(30).toList(growable: false);
      setState(() {
        if (colombia) {
          _colombiaTop = visibleChart;
          category.tracks = visibleChart
              .skip(1)
              .map((track) => _chartTrackToOnlineTrack(track, 'colombia'))
              .toList(growable: false);
        } else {
          _worldTop = visibleChart;
          _worldArtists = artistTrends ?? _worldArtists;
          category.tracks = visibleChart
              .map((track) => _chartTrackToOnlineTrack(track, 'world'))
              .toList(growable: false);
        }
        category.loading = false;
        category.error = category.tracks.isEmpty
            ? 'No se pudo cargar el chart. Intenta actualizar.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        category.loading = false;
        category.error = category.tracks.isEmpty
            ? 'No se pudo cargar el chart. Revisa tu conexión.'
            : null;
      });
    }
  }

  _OnlineTrack _chartTrackToOnlineTrack(HomeChartTrack track, String session) =>
      _OnlineTrack(
        videoId: 'chart:$session:${track.id}',
        title: track.title,
        artist: track.artist,
        thumbnail: track.artworkUrl,
        durationSeconds: 0,
        chartRank: track.rank,
        chartKey: 'chart:$session:${track.id}',
      );

  Future<void> _playHomeChartTrack(
    HomeChartTrack chartTrack, {
    required List<HomeChartTrack> chart,
    required String session,
  }) async {
    final chartKey = 'chart:$session:${chartTrack.id}';
    setState(() => _resolvingChartKey = chartKey);
    try {
      final selected = await _resolveHomeChartTrack(
        chartTrack,
        session: session,
      );
      if (!mounted) return;
      if (selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No encontramos una versión que coincida con esta canción.',
            ),
          ),
        );
        return;
      }
      await _playOnlineTrack(selected, queue: [selected], queueIndex: 0);
      final playbackRequestId = _onlinePlaybackRequestId;
      unawaited(
        _extendHomeChartQueue(
          chartTrack,
          chart,
          selected,
          playbackRequestId,
          session,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo buscar este tema ahora.')),
      );
    } finally {
      if (mounted && _resolvingChartKey == chartKey) {
        setState(() => _resolvingChartKey = null);
      }
    }
  }

  String _normalizeChartText(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(
        RegExp(r'\b(topic|official|audio|video|lyrics?|vevo|visualizer)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Set<String> _chartWords(String value) =>
      _normalizeChartText(value)
          .split(' ')
          .where((word) => word.length > 1)
          .toSet();

  double _chartTitleMatch(String resultTitle, String wantedTitle) {
    final result = _normalizeChartText(resultTitle);
    final wanted = _normalizeChartText(wantedTitle);
    if (result.isEmpty || wanted.isEmpty) return 0;
    if (result == wanted) return 1;
    final wantedWords = _chartWords(wanted);
    if (wantedWords.isEmpty) return 0;
    return _chartWords(result).intersection(wantedWords).length /
        wantedWords.length;
  }

  double _chartArtistMatch(
    String resultTitle,
    String resultArtist,
    String artist,
  ) {
    const ignored = {
      'and',
      'y',
      'feat',
      'ft',
      'con',
      'de',
      'del',
      'la',
      'las',
      'el',
      'los',
      'the',
    };
    final wantedWords = _chartWords(artist)..removeAll(ignored);
    if (wantedWords.isEmpty) return 0;
    final resultWords = _chartWords('$resultTitle $resultArtist');
    return resultWords.intersection(wantedWords).length / wantedWords.length;
  }

  double _chartVersionPenalty(String title, String wantedTitle) {
    const variantTokens = {
      'live',
      'remix',
      'acoustic',
      'cover',
      'karaoke',
      'nightcore',
      'slowed',
      'reverb',
      'sped',
      'instrumental',
      'extended',
      '8d',
    };
    final resultWords = _chartWords(title);
    final wantedWords = _chartWords(wantedTitle);
    return resultWords
            .difference(wantedWords)
            .intersection(variantTokens)
            .isEmpty
        ? 0
        : .45;
  }

  String _homeChartTrackKey(HomeChartTrack track) =>
      '${_normalizeChartText(track.title)}|${_normalizeChartText(track.artist)}';

  Future<_OnlineTrack?> _resolveHomeChartTrack(
    HomeChartTrack track, {
    String session = 'global',
  }) async {
    if (track.title.trim().isEmpty || track.artist.trim().isEmpty) return null;
    final key = _homeChartTrackKey(track);
    final cached = _resolvedHomeChartTracks[key];
    if (cached != null) {
      return _OnlineTrack(
        videoId: cached.videoId,
        title: cached.title,
        artist: cached.artist,
        thumbnail: track.artworkUrl.isNotEmpty
            ? track.artworkUrl
            : cached.thumbnail,
        durationSeconds: cached.durationSeconds,
        chartKey: 'chart:$session:${track.id}',
      );
    }

    final candidates = <dynamic>[];
    final seenVideoIds = <String>{};
    final queries = [
      '${track.title} ${track.artist} audio',
      '${track.title} ${track.artist}',
      track.title,
    ];
    for (final query in queries) {
      try {
        final batch = await _youtube.search
            .search(query)
            .timeout(const Duration(seconds: 18));
        var confidentCanonicalMatch = false;
        for (final candidate in batch) {
          if (candidate.id.value.isNotEmpty &&
              seenVideoIds.add(candidate.id.value)) {
            candidates.add(candidate);
          }
          confidentCanonicalMatch =
              confidentCanonicalMatch ||
              (_chartTitleMatch(candidate.title, track.title) >= .72 &&
                  _chartArtistMatch(
                        candidate.title,
                        candidate.author,
                        track.artist,
                      ) >=
                      .25 &&
                  _chartVersionPenalty(candidate.title, track.title) == 0);
        }
        if (confidentCanonicalMatch) break;
      } catch (_) {
        // Try the next query form; a single failed search should not end resolution.
      }
    }
    if (candidates.isEmpty) return null;

    dynamic best;
    var bestScore = -1.0;
    var bestTitleScore = 0.0;
    var bestArtistScore = 0.0;
    for (final candidate in candidates) {
      final titleScore = _chartTitleMatch(candidate.title, track.title);
      final artistScore = _chartArtistMatch(
        candidate.title,
        candidate.author,
        track.artist,
      );
      final score =
          titleScore * .7 +
          artistScore * .3 -
          _chartVersionPenalty(candidate.title, track.title);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
        bestTitleScore = titleScore;
        bestArtistScore = artistScore;
      }
    }

    // Refuse weak matches instead of silently playing a different song.
    if (best == null ||
        !(bestTitleScore >= .72 && bestArtistScore >= .25) &&
            !(bestTitleScore >= .9 && bestArtistScore == 0) ||
        bestScore < .7) {
      return null;
    }
    final resolved = _OnlineTrack(
      videoId: best.id.value,
      title: best.title,
      artist: best.author,
      thumbnail: track.artworkUrl.isNotEmpty
          ? track.artworkUrl
          : best.thumbnails.highResUrl,
      durationSeconds: best.duration?.inSeconds ?? 0,
      chartKey: 'chart:$session:${track.id}',
    );
    _resolvedHomeChartTracks[key] = resolved;
    return resolved;
  }

  Future<void> _extendHomeChartQueue(
    HomeChartTrack current,
    List<HomeChartTrack> chart,
    _OnlineTrack selected,
    int playbackRequestId,
    String session,
  ) async {
    final start = chart.indexWhere((track) => track.id == current.id);
    if (start < 0) return;
    final ordered = [...chart.skip(start), ...chart.take(start)];
    final uniqueTracks = <HomeChartTrack>[];
    final seenSongs = <String>{};
    for (final track in ordered) {
      if (seenSongs.add(_homeChartTrackKey(track))) uniqueTracks.add(track);
      if (uniqueTracks.length == 6) break;
    }
    final resolved = await Future.wait(
      uniqueTracks.map(
        (track) => _resolveHomeChartTrack(track, session: session),
      ),
    );
    final queue = <_OnlineTrack>[];
    final seenVideoIds = <String>{};
    final seenResolvedSongs = <String>{};
    for (var index = 0; index < resolved.length; index++) {
      final item = resolved[index];
      if (item == null || !seenVideoIds.add(item.videoId)) continue;
      final resolvedSongKey =
          '${_normalizeChartText(item.title)}|${_normalizeChartText(item.artist)}';
      if (!seenResolvedSongs.add(resolvedSongKey)) continue;
      queue.add(
        _OnlineTrack(
          videoId: item.videoId,
          title: item.title,
          artist: item.artist,
          thumbnail: uniqueTracks[index].artworkUrl.isNotEmpty
              ? uniqueTracks[index].artworkUrl
              : item.thumbnail,
          durationSeconds: item.durationSeconds,
          chartKey: item.chartKey,
        ),
      );
    }
    if (queue.isEmpty) queue.add(selected);
    if (!mounted ||
        playbackRequestId != _onlinePlaybackRequestId ||
        _playingOnlineTrack?.videoId != selected.videoId) {
      return;
    }
    setState(() {
      _onlinePlaybackQueue = queue;
      _onlineQueueIndex = 0;
    });
  }

  Future<void> _playHomePodcastRequest(HomePodcastPlayRequest request) async {
    if (request.index < 0 || request.index >= request.episodes.length) return;
    final queue = request.episodes
        .map(
          (episode) => _OnlineTrack(
            videoId: 'podcast:${episode.id}',
            title: episode.title,
            artist: episode.showTitle,
            thumbnail: episode.artworkUrl,
            durationSeconds: episode.durationSeconds,
            directAudioUrl: episode.audioUrl,
          ),
        )
        .toList(growable: false);
    await _playOnlineTrack(
      queue[request.index],
      queue: queue,
      queueIndex: request.index,
    );
  }

  Future<void> _playOnlineTrack(
    _OnlineTrack track, {
    List<_OnlineTrack>? queue,
    int? queueIndex,
  }) async {
    if (_usingMediaKitForLocalAudio) {
      await _localAudioFallback.stop();
      _usingMediaKitForLocalAudio = false;
    }
    final keepVideoMode = _videoMode;
    if (keepVideoMode) {
      _videoPlaybackRequestId++;
      _videoAudioSyncTimer?.cancel();
      await _videoPlayer.stop();
    }
    _videoLoading = false;
    final requestId = ++_onlinePlaybackRequestId;
    _beginListeningSession();
    _onlineDebounce?.cancel();
    _queue.clear();
    _currentIndex = null;
    if (queue != null) _onlinePlaybackQueue = List.of(queue);
    if (_onlinePlaybackQueue.isEmpty) _onlinePlaybackQueue = [track];
    _onlineQueueIndex =
        queueIndex ??
        _onlinePlaybackQueue.indexWhere(
          (item) => item.videoId == track.videoId,
        );
    setState(() {
      _playingOnlineTrack = track;
      _onlinePlaybackLoading = true;
      _error = null;
      _duration = null;
    });
    unawaited(_updateArtworkPalette());
    try {
      await _writePlaybackLog('Resolving online audio stream');
      await _player.stop();
      AudioSource? directSource = track.directAudioUrl == null
          ? null
          : AudioSource.uri(Uri.parse(track.directAudioUrl!));
      File? audioFile = directSource == null
          ? await _getCachedOnlineAudio(track)
          : null;
      if (requestId != _onlinePlaybackRequestId) return;
      Object? nativeExtractorError;

      if (audioFile == null && directSource == null) {
        try {
          final cachedExtraction = _prefetchedOnlineAudio.remove(track.videoId);
          final extracted =
              cachedExtraction != null &&
                  DateTime.now().difference(cachedExtraction.resolvedAt) <
                      const Duration(hours: 2)
              ? cachedExtraction
              : await _resolveNativeOnlineAudio(track.videoId);
          if (requestId != _onlinePlaybackRequestId) return;
          if (extracted != null) {
            await _writePlaybackLog(
              'NewPipe resolved audio: type=${extracted.contentType}, bitrate=${extracted.bitrate}; streaming directly',
            );
            // The Windows WinRT player rejects native request headers. The
            // NewPipe URL is signed and can be streamed directly without
            // attaching headers to the platform source.
            directSource = AudioSource.uri(Uri.parse(extracted.url));
          }
        } catch (error) {
          nativeExtractorError = error;
          await _writePlaybackLog('Native NewPipe extraction failed: $error');
        }
      }

      if (audioFile == null && directSource == null) {
        try {
          final manifest = await _resolveOnlineManifest(track.videoId);
          if (requestId != _onlinePlaybackRequestId) return;
          final mp4Audio = manifest.audioOnly.where(
            (stream) => stream.container == StreamContainer.mp4,
          );
          final audio = (mp4Audio.isEmpty ? manifest.audioOnly : mp4Audio)
              .withHighestBitrate();
          await _writePlaybackLog(
            'Dart extractor resolved: container=${audio.container.name}, codec=${audio.codec.mimeType}, audioOnly=${manifest.audioOnly.length}',
          );
          audioFile = await _cacheOnlineAudio(track, audio, requestId);
        } catch (fallbackError) {
          if (nativeExtractorError != null) {
            throw StateError(
              'NewPipe: $nativeExtractorError; Dart: $fallbackError',
            );
          }
          rethrow;
        }
      }

      if (audioFile == null) {
        if (directSource == null) {
          throw StateError(
            'No se pudo extraer un stream de audio para este video.',
          );
        }
      }
      if (requestId != _onlinePlaybackRequestId) return;
      if (audioFile != null) {
        await _writePlaybackLog(
          'Using cached online audio: bytes=${await audioFile.length()}',
        );
      }
      await _player.setAudioSource(
        directSource ?? AudioSource.file(audioFile!.path),
      );
      if (requestId != _onlinePlaybackRequestId) return;
      unawaited(_startOnlinePlayback(requestId));
      _currentIndex = null;
      if (mounted) setState(() => _onlinePlaybackLoading = false);
      await _writePlaybackLog('Audio source loaded; playback requested');
      if (keepVideoMode && mounted) {
        unawaited(_playVideoPreview(null, track));
      }
    } catch (error) {
      if (!mounted || requestId != _onlinePlaybackRequestId) return;
      await _writePlaybackLog('Online playback setup failed: $error');
      final detail = error.toString().toLowerCase();
      final message =
          detail.contains('not a bot') || detail.contains('sign in to confirm')
          ? 'El servicio de música bloqueó esta solicitud automática. Prueba otro resultado o inténtalo más tarde.'
          : error is VideoUnplayableException
          ? 'No se pudo obtener audio reproducible para esta canción. Prueba otro resultado o inténtalo más tarde.'
          : 'No se pudo obtener o reproducir el audio online. Intenta con otro resultado. ($error)';
      setState(() {
        _onlinePlaybackLoading = false;
        _error = message;
      });
    }
  }

  Future<void> _skipOnlineTrack(int direction) async {
    if (_onlineAdvancing || _playingOnlineTrack == null) return;
    final nextIndex = _onlineQueueIndex + direction;
    if (nextIndex < 0 || nextIndex >= _onlinePlaybackQueue.length) return;
    _onlineAdvancing = true;
    try {
      await _playOnlineTrack(
        _onlinePlaybackQueue[nextIndex],
        queue: _onlinePlaybackQueue,
        queueIndex: nextIndex,
      );
    } finally {
      _onlineAdvancing = false;
    }
  }

  Future<void> _skipMiniPlayerTrack(int direction) async {
    if (_usingMediaKitForLocalAudio) {
      final previousIndex = _localAudioFallback.state.playlist.index;
      if (direction < 0) {
        await _localAudioFallback.previous();
      } else {
        await _localAudioFallback.next();
      }
      final nextIndex = _localAudioFallback.state.playlist.index;
      if (_videoMode && nextIndex != previousIndex && nextIndex >= 0) {
        final path = nextIndex < _queue.length ? _queue[nextIndex] : null;
        final nextTrack = path == null
            ? null
            : _tracks.where((track) => track.path == path).firstOrNull;
        if (nextTrack != null) await _playVideoPreview(nextTrack, null);
      }
      return;
    }
    final wasVideoMode = _videoMode;
    final previousIndex = _player.currentIndex;
    if (wasVideoMode) {
      _videoPlaybackRequestId++;
      _videoAudioSyncTimer?.cancel();
      await _videoPlayer.stop();
    }

    if (_playingOnlineTrack != null) {
      await _skipOnlineTrack(direction);
      return;
    }

    if (direction < 0) {
      await _player.seekToPrevious();
    } else {
      await _player.seekToNext();
    }
    final nextIndex = _player.currentIndex;
    if (wasVideoMode &&
        nextIndex != null &&
        (nextIndex != previousIndex || direction < 0) &&
        nextIndex >= 0 &&
        nextIndex < _queue.length &&
        mounted) {
      final path = _queue[nextIndex];
      final nextTrack = _tracks
          .where((track) => track.path == path)
          .firstOrNull;
      if (nextTrack != null) await _playVideoPreview(nextTrack, null);
    }
  }

  Future<void> _toggleMiniPlayerPlayback(bool wasPlaying) async {
    if (_usingMediaKitForLocalAudio) {
      if (wasPlaying) {
        await _localAudioFallback.pause();
        if (_videoMode) await _videoPlayer.pause();
      } else {
        await _localAudioFallback.play();
        if (_videoMode) await _videoPlayer.play();
      }
      return;
    }
    if (_videoMode) {
      if (wasPlaying) {
        await _videoPlayer.pause();
        await _player.pause();
      } else {
        await _videoPlayer.play();
        await _player.play();
      }
      return;
    }
    if (wasPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekMiniPlayer(Duration position) async {
    if (_usingMediaKitForLocalAudio) {
      await _localAudioFallback.seek(position);
    } else {
      await _player.seek(position);
    }
    if (_videoMode) {
      await _videoPlayer.seek(position);
    }
  }

  Future<_ResolvedOnlineAudio?> _resolveNativeOnlineAudio(
    String videoId,
  ) async {
    final current = _prefetchedOnlineAudio[videoId];
    if (current != null &&
        DateTime.now().difference(current.resolvedAt) <
            const Duration(hours: 2)) {
      return current;
    }
    final pending = _onlineExtractionJobs[videoId];
    if (pending != null) return pending;

    final future = _extractWithNativeNewPipe(videoId);
    _onlineExtractionJobs[videoId] = future;
    try {
      return await future;
    } finally {
      if (identical(_onlineExtractionJobs[videoId], future)) {
        _onlineExtractionJobs.remove(videoId);
      }
    }
  }

  Future<void> _prefetchNextOnlineTrack(int requestId) async {
    final nextIndex = _onlineQueueIndex + 1;
    if (requestId != _onlinePlaybackRequestId ||
        nextIndex < 0 ||
        nextIndex >= _onlinePlaybackQueue.length) {
      return;
    }
    final currentId = _playingOnlineTrack?.videoId;
    final next = _onlinePlaybackQueue[nextIndex];
    if (next.videoId == currentId || next.directAudioUrl != null) return;

    final prepared = _prefetchedOnlineAudio[next.videoId];
    if (prepared != null &&
        DateTime.now().difference(prepared.resolvedAt) <
            const Duration(hours: 2)) {
      return;
    }
    try {
      final cache = await _onlineAudioCacheFile(next);
      if (await cache.exists() && await cache.length() > 0) return;
      if (requestId != _onlinePlaybackRequestId) return;
      final audio = await _resolveNativeOnlineAudio(next.videoId);
      if (audio != null &&
          requestId == _onlinePlaybackRequestId &&
          _playingOnlineTrack?.videoId == currentId) {
        _prefetchedOnlineAudio[next.videoId] = audio;
        await _writePlaybackLog(
          'Prepared next online track in memory: video=${next.videoId}',
        );
      }
    } catch (error) {
      await _writePlaybackLog('Next online track prefetch failed: $error');
    }
  }

  Future<StreamManifest> _resolveOnlineManifest(String videoId) async {
    final clients = <(String, YoutubeApiClient, bool)>[
      ('Android página', YoutubeApiClient.androidSdkless, true),
      ('Android API', YoutubeApiClient.androidSdkless, false),
      ('TV', YoutubeApiClient.tv, false),
      ('iOS', YoutubeApiClient.ios, false),
      ('Android VR', YoutubeApiClient.androidVr, false),
      ('Safari', YoutubeApiClient.safari, false),
    ];
    Object? lastError;
    for (final (name, client, requireWatchPage) in clients) {
      try {
        await _writePlaybackLog('Trying YouTube extraction client: $name');
        final manifest = await _youtube.videos.streamsClient
            .getManifest(
              videoId,
              ytClients: [client],
              requireWatchPage: requireWatchPage,
            )
            .timeout(const Duration(seconds: 20));
        if (manifest.audioOnly.isNotEmpty) {
          await _writePlaybackLog(
            'YouTube extraction client $name returned ${manifest.audioOnly.length} audio streams',
          );
          return manifest;
        }
        lastError = StateError('El cliente $name no ofreció audio disponible.');
      } catch (error) {
        lastError = error;
        await _writePlaybackLog('YouTube client $name failed: $error');
      }
    }
    if (lastError is Error && lastError.stackTrace != null) {
      Error.throwWithStackTrace(lastError, lastError.stackTrace!);
    }
    throw lastError ?? StateError('YouTube no ofreció audio para este video.');
  }

  Future<_ResolvedOnlineAudio?> _extractWithNativeNewPipe(
    String videoId,
  ) async {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final jar = File(
      '${appDirectory.path}${Platform.pathSeparator}soundneed-newpipe-extractor-all.jar',
    );
    if (!await jar.exists()) {
      await _writePlaybackLog('Native NewPipe helper is not bundled');
      throw StateError(
        'El extractor NewPipe no está junto al ejecutable. Comprueba que la compilación de Windows haya generado y copiado soundneed-newpipe-extractor-all.jar.',
      );
    }

    final java = await _findJavaExecutable();
    if (java == null) {
      await _writePlaybackLog('No Java runtime found for NewPipe helper');
      throw StateError(
        'No se encontró Java para iniciar el extractor NewPipe.',
      );
    }

    final process = await Process.start(java, [
      '-jar',
      jar.path,
      videoId,
    ], runInShell: false);
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        process.kill();
        throw TimeoutException('NewPipe tardó más de 45 segundos.');
      },
    );
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw ProcessException(
        java,
        ['-jar', jar.path, videoId],
        stderr.trim().isEmpty
            ? 'NewPipe no pudo extraer el audio.'
            : stderr.trim(),
        exitCode,
      );
    }

    final lines = stdout.trim().split(RegExp(r'\r?\n'));
    if (lines.length < 3) {
      throw FormatException(
        'NewPipe devolvió una respuesta incompleta: $stderr',
      );
    }
    final url = lines[lines.length - 3].trim();
    final contentType = lines[lines.length - 2].trim();
    final bitrate = int.tryParse(lines.last.trim()) ?? 0;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw FormatException('NewPipe no devolvió una URL de audio válida.');
    }
    return _ResolvedOnlineAudio(
      url: url,
      contentType: contentType,
      bitrate: bitrate,
    );
  }

  Future<Uri> _extractNativeNewPipeVideo(String videoId) async {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final jar = File(
      '${appDirectory.path}${Platform.pathSeparator}soundneed-newpipe-extractor-all.jar',
    );
    if (!await jar.exists()) {
      throw StateError('No se encontró el extractor de video NewPipe.');
    }
    final java = await _findJavaExecutable();
    if (java == null) {
      throw StateError('No se encontró Java para el extractor de video.');
    }

    final arguments = ['-jar', jar.path, videoId, 'video'];
    final process = await Process.start(java, arguments, runInShell: false);
    final stdoutFuture = utf8.decoder.bind(process.stdout).join();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        process.kill();
        throw TimeoutException('NewPipe tardó demasiado al resolver el video.');
      },
    );
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw ProcessException(
        java,
        arguments,
        stderr.trim().isEmpty
            ? 'NewPipe no pudo extraer el video.'
            : stderr.trim(),
        exitCode,
      );
    }
    final lines = stdout.trim().split(RegExp(r'\r?\n'));
    final uri = lines.isEmpty ? null : Uri.tryParse(lines.first.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw FormatException('NewPipe no devolvió una URL de video válida.');
    }
    return uri;
  }

  Future<String?> _findJavaExecutable() async {
    final candidates = <String>[
      if (Platform.environment['JAVA_HOME'] case final javaHome?)
        '$javaHome${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe',
      if (Platform.environment['ProgramFiles'] case final programFiles?)
        '$programFiles${Platform.pathSeparator}Android${Platform.pathSeparator}Android Studio${Platform.pathSeparator}jbr${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe',
      if (Platform.environment['LOCALAPPDATA'] case final localAppData?)
        '$localAppData${Platform.pathSeparator}Programs${Platform.pathSeparator}Android Studio${Platform.pathSeparator}jbr${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    try {
      final result = await Process.run('java.exe', ['-version']);
      if (result.exitCode == 0) return 'java.exe';
    } catch (_) {
      // The app can still use the Dart extractor fallback without Java.
    }
    return null;
  }

  Future<File?> _cacheOnlineAudio(
    _OnlineTrack track,
    AudioOnlyStreamInfo audio,
    int requestId,
  ) async {
    final file = await _onlineAudioCacheFile(track);
    if (await file.exists() && await file.length() > 0) return file;
    await _writePlaybackLog(
      'Downloading YouTube audio to disk cache: video=${track.videoId}',
    );
    return _writeOnlineAudioCache(
      track,
      file,
      _youtube.videos.streamsClient
          .get(audio)
          .timeout(const Duration(minutes: 5)),
      requestId,
    );
  }

  Future<File?> _writeOnlineAudioCache(
    _OnlineTrack track,
    File file,
    Stream<List<int>> bytes,
    int requestId,
  ) async {
    final sink = file.openWrite();
    var bytesWritten = 0;
    try {
      await for (final chunk in bytes) {
        if (requestId != _onlinePlaybackRequestId) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return null;
        }
        sink.add(chunk);
        bytesWritten += chunk.length;
      }
      await sink.flush();
      await sink.close();
      if (bytesWritten == 0) {
        throw StateError('YouTube entregó un flujo de audio vacío.');
      }
      return file;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<File> _onlineAudioCacheFile(_OnlineTrack track) async {
    final support = await getApplicationSupportDirectory();
    final cache = Directory(
      '${support.path}${Platform.pathSeparator}online-audio-cache',
    );
    await cache.create(recursive: true);
    final key = sha1.convert(utf8.encode(track.videoId)).toString();
    return File('${cache.path}${Platform.pathSeparator}$key.mp4');
  }

  Future<File?> _getCachedOnlineAudio(_OnlineTrack track) async {
    final file = await _onlineAudioCacheFile(track);
    if (await file.exists() && await file.length() > 0) {
      await _writePlaybackLog(
        'Using cached online audio: video=${track.videoId}',
      );
      return file;
    }
    return null;
  }

  Future<void> _startOnlinePlayback(int requestId) async {
    try {
      unawaited(_prefetchNextOnlineTrack(requestId));
      await _player.play();
    } catch (error) {
      if (requestId != _onlinePlaybackRequestId) return;
      await _writePlaybackLog('Online playback failed: $error');
      if (mounted) {
        setState(() {
          _onlinePlaybackLoading = false;
          _error = 'Falló la reproducción de audio online: $error';
        });
      }
    }
  }

  String _time(Duration? duration) {
    if (duration == null || duration.isNegative) return '--:--';
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _videoAudioSyncTimer?.cancel();
    _exploreMeterTimer?.cancel();
    unawaited(
      _windowChannel
          .invokeMethod<void>('stopOutputSpectrum')
          .catchError((_) {}),
    );
    _localAudioPositionSubscription?.cancel();
    _localAudioDurationSubscription?.cancel();
    _localAudioPlaylistSubscription?.cancel();
    _indexSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _errorSubscription?.cancel();
    _pruneTimer?.cancel();
    _onlineDebounce?.cancel();
    _onlineRequestId++;
    _onlinePlaybackRequestId++;
    _search.dispose();
    _position.dispose();
    _youtube.close();
    _player.dispose();
    unawaited(_videoPlayer.dispose());
    final localAudioFallback = _localAudioFallbackPlayer;
    if (localAudioFallback != null) unawaited(localAudioFallback.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current =
        _currentIndex != null &&
            _currentIndex! >= 0 &&
            _currentIndex! < _queue.length
        ? _tracks
              .where((track) => track.path == _queue[_currentIndex!])
              .firstOrNull
        : null;
    final ImageProvider<Object>? ambientArtwork =
        _playingOnlineTrack != null && _playingOnlineTrack!.thumbnail.isNotEmpty
        ? NetworkImage(_playingOnlineTrack!.thumbnail)
        : current?.coverPath == null
        ? null
        : FileImage(File(current!.coverPath!));
    final videoReadyForCurrentTrack =
        _videoMode &&
        !_videoPreviewUnavailable &&
        _videoReadyTrackKey == _videoTrackKey(current, _playingOnlineTrack);
    return Scaffold(
      backgroundColor: _bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 850;
          // Windows scaling can make a 1920 px display report only about
          // 1280 logical pixels, so show the third panel at this breakpoint.
          final hasNowPlaying =
              constraints.maxWidth >= 1150 &&
              (current != null || _playingOnlineTrack != null);
          final exploring = _section == 'Explorar';
          final showNowPlaying =
              hasNowPlaying && !_nowPlayingCollapsed && !exploring;
          return Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: ColoredBox(color: _bg)),
              Positioned.fill(
                child: _videoMode
                    ? RepaintBoundary(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                // Blur at a smaller resolution, then scale the
                                // softened video to fill the desktop backdrop.
                                width: 640,
                                height: 360,
                                child: ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 12,
                                    sigmaY: 12,
                                  ),
                                  child: media_video.Video(
                                    controller: _videoController,
                                    fit: BoxFit.cover,
                                    controls: media_video.NoVideoControls,
                                  ),
                                ),
                              ),
                            ),
                            const DecoratedBox(decoration: _videoBackdropShade),
                          ],
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: double.infinity,
                          height: constraints.maxHeight * .7,
                          child: AmbientAlbumBackground(
                            artwork: ambientArtwork,
                          ),
                        ),
                      ),
              ),
              Column(
                children: [
                  SoundNeedTopBar(
                    compact: compact,
                    section: _section,
                    query: _query,
                    searchController: _search,
                    onSearchChanged: _onSearchChanged,
                    scanning: _scanning,
                    onlineMode: _onlineMode,
                    maximized: _windowMaximized,
                    backgroundColor: _bg,
                    surfaceColor: _raised,
                    accentColor: _cyan,
                    mutedColor: _muted,
                    onHome: () => setState(() {
                      _section = 'Inicio';
                      _playlistView = null;
                    }),
                    onSettings: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Configuración'),
                        content: SingleChildScrollView(child: _settingsPanel()),
                      ),
                    ),
                    onNotifications: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Notificaciones'),
                        content: const Text('No tienes notificaciones nuevas.'),
                      ),
                    ),
                    onExplore: () => _navigate('Explorar'),
                    onMinimize: () => unawaited(
                      _windowChannel.invokeMethod<void>('minimize'),
                    ),
                    onToggleMaximize: () => unawaited(_toggleWindowMaximize()),
                    onClose: () => unawaited(_closeApp()),
                    onDragWindow: () =>
                        unawaited(_windowChannel.invokeMethod<void>('drag')),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                MouseRegion(
                                  onEnter: exploring
                                      ? (_) => setState(
                                          () => _exploreSidebarHovered = true,
                                        )
                                      : null,
                                  onExit: exploring
                                      ? (_) => setState(
                                          () => _exploreSidebarHovered = false,
                                        )
                                      : null,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeInOutCubic,
                                    width: exploring && !_exploreSidebarHovered
                                        ? 14
                                        : ((_sidebarCompactOverride ?? compact)
                                              ? 84
                                              : 254),
                                    clipBehavior: Clip.hardEdge,
                                    decoration: const BoxDecoration(),
                                    child: exploring && !_exploreSidebarHovered
                                        ? const SizedBox.expand()
                                        : SoundNeedSidebar(
                                            compact:
                                                _sidebarCompactOverride ??
                                                compact,
                                            section: _section,
                                            playlistView: _playlistView,
                                            playlistNames: _playlists.keys
                                                .toList(),
                                            panelColor: _panel,
                                            accentColor: _cyan,
                                            mutedColor: _muted,
                                            onNavigate: _navigate,
                                            collapsed:
                                                _sidebarCompactOverride ??
                                                compact,
                                            onTogglePanel: (collapsed) =>
                                                setState(
                                                  () =>
                                                      _sidebarCompactOverride =
                                                          collapsed,
                                                ),
                                          ),
                                  ),
                                ),
                                Expanded(
                                  child: _mainContent(compact, showNowPlaying),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeInOutCubic,
                                  width: hasNowPlaying && !exploring
                                      ? (showNowPlaying ? 326 : 64)
                                      : 0,
                                  child: ClipRect(
                                    child: SizedBox.expand(
                                      child: Stack(
                                        children: [
                                          if (showNowPlaying)
                                            Positioned.fill(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 13,
                                                ),
                                                child: AnimatedSlide(
                                                  duration: const Duration(
                                                    milliseconds: 380,
                                                  ),
                                                  curve: Curves.easeInOutCubic,
                                                  offset: Offset.zero,
                                                  child: _nowPlayingPanel(
                                                    current,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (hasNowPlaying &&
                                              _nowPlayingCollapsed)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              bottom: 0,
                                              child: _NowPlayingEdgeToggle(
                                                onPressed: () => setState(
                                                  () => _nowPlayingCollapsed =
                                                      false,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 4 : 10,
                              12,
                              compact ? 4 : 10,
                              12,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: _miniPlayer(current, compact),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  HomeOnlineSection _homeOnlineSection(
    _HomeOnlineCategory category, {
    required String title,
    required String subtitle,
    bool ranked = false,
    ValueChanged<int>? onPlay,
    VoidCallback? onRefresh,
  }) {
    final results = category.tracks
        .map(
          (track) => OnlineSearchResult(
            videoId: track.videoId,
            title: track.title,
            artist: track.artist,
            thumbnail: track.thumbnail,
            durationSeconds: track.durationSeconds,
            rank: track.chartRank,
          ),
        )
        .toList(growable: false);

    return HomeOnlineSection(
      title: title,
      subtitle: subtitle,
      results: results,
      loading: category.loading,
      error: category.error,
      ranked: ranked,
      onRefresh:
          onRefresh ??
          () => unawaited(_loadHomeCategory(category, refresh: true)),
      onPlay:
          onPlay ??
          (index) => unawaited(
            _playOnlineTrack(
              category.tracks[index],
              queue: category.tracks,
              queueIndex: index,
            ),
          ),
    );
  }

  Widget _mainContent(bool compact, bool hasNowPlayingPanel) {
    final tracks = _visibleTracks;
    final title = _section == 'Playlists' && _playlistView != null
        ? _playlistView!
        : _section;
    final Widget libraryBody = _loading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(64),
              child: CircularProgressIndicator(color: _cyan),
            ),
          )
        : _section == 'Buscar'
        ? _searchResultsPanel(tracks, compact)
        : tracks.isEmpty
        ? _emptyState()
        : _trackTable(tracks, compact, neutralHome: _section == 'Inicio');
    final config = LibraryPageConfig(
      compact: compact,
      hasNowPlayingPanel: hasNowPlayingPanel,
      title: title,
      accentColor: _appPalette.primary,
      secondaryColor: _appPalette.secondary,
      playlistView: _playlistView,
      trackCount: tracks.length,
      onCreatePlaylist: _createPlaylist,
      playlistNames: _playlists.keys.toList(growable: false),
      playlistCounts: {
        for (final entry in _playlists.entries) entry.key: entry.value.length,
      },
      onOpenPlaylist: _navigate,
      onRenamePlaylist: (name) => unawaited(_renamePlaylist(name)),
      onDeletePlaylist: (name) => unawaited(_deletePlaylist(name)),
      body: libraryBody,
      error: _error,
      onDismissError: () => setState(() => _error = null),
      queueOpen: _queueOpen,
      queuePanel: _queuePanel(),
    );

    return switch (_section) {
      'Inicio' => HomePage(
        config: config,
        colombiaChart: _homeOnlineSection(
          _colombiaChart,
          title: 'Top Colombia',
          subtitle: '',
          ranked: true,
          onRefresh: () => unawaited(
            _loadHomeChart(_colombiaChart, colombia: true, refresh: true),
          ),
          onPlay: (index) => unawaited(
            _playHomeChartTrack(
              _colombiaTop[index + 1],
              chart: _colombiaTop,
              session: 'colombia',
            ),
          ),
        ),
        worldChart: _homeOnlineSection(
          _worldChart,
          title: 'Top mundial',
          subtitle: '',
          ranked: true,
          onRefresh: () => unawaited(
            _loadHomeChart(_worldChart, colombia: false, refresh: true),
          ),
          onPlay: (index) => unawaited(
            _playHomeChartTrack(
              _worldTop[index],
              chart: _worldTop,
              session: 'world',
            ),
          ),
        ),
        discoverMusic: _homeOnlineSection(
          _discoverMusic,
          title: 'Música del momento',
          subtitle: '',
        ),
        onPlayPodcast: (request) => unawaited(_playHomePodcastRequest(request)),
        topTrack: _colombiaTop.isEmpty
            ? null
            : OnlineSearchResult(
                videoId: 'chart:colombia:${_colombiaTop.first.id}',
                title: _colombiaTop.first.title,
                artist: _colombiaTop.first.artist,
                thumbnail: _colombiaTop.first.artworkUrl,
                durationSeconds: 0,
                rank: _colombiaTop.first.rank,
              ),
        onPlayTopTrack: _colombiaTop.isEmpty
            ? null
            : () => unawaited(
                _playHomeChartTrack(
                  _colombiaTop.first,
                  chart: _colombiaTop,
                  session: 'colombia',
                ),
              ),
        playingVideoId:
            _playingOnlineTrack?.chartKey ?? _playingOnlineTrack?.videoId,
        isPlaying: _player.playing,
        loadingVideoId:
            _resolvingChartKey ??
            (_onlinePlaybackLoading
                ? _playingOnlineTrack?.chartKey ?? _playingOnlineTrack?.videoId
                : null),
        continueTitle: _playingOnlineTrack?.title ?? _currentLocalTrack?.title,
        continueArtist:
            _playingOnlineTrack?.artist ?? _currentLocalTrack?.artist,
        onContinue: _playingOnlineTrack == null && _currentLocalTrack == null
            ? null
            : () => unawaited(_player.play()),
        stationArtists: _tracks
            .map((track) => track.artist.trim())
            .where(
              (artist) =>
                  artist.isNotEmpty &&
                  artist.toLowerCase() != 'artista desconocido' &&
                  artist.toLowerCase() != 'unknown artist',
            )
            .toSet()
            .take(6)
            .toList(growable: false),
        onSurpriseMix: () => unawaited(_playSurpriseMix()),
        onPlayStation: (artist) => unawaited(_playArtistStation(artist)),
        onNavigate: _navigate,
      ),
      'Explorar' =>
        _exploreShowingTrack
            ? ExplorePage(
                config: config,
                track: _currentLocalTrack,
                onlineArtwork: _playingOnlineTrack?.thumbnail,
                spectrum: _exploreSpectrum,
                onBackToDiscoveries: _returnToExploreDiscoveries,
                recommendations: _exploreFeed.recommendations,
                recommendationsLoading: _exploreRecommendationsLoading,
                onPlayRecommendation: (recommendation) =>
                    unawaited(_playExploreRecommendation(recommendation)),
                onPrevious: () => unawaited(_skipMiniPlayerTrack(-1)),
                onNext: () => unawaited(_skipMiniPlayerTrack(1)),
                canGoPrevious: _playingOnlineTrack != null
                    ? _onlineQueueIndex > 0
                    : (_currentIndex ?? 0) > 0,
                canGoNext: _playingOnlineTrack != null
                    ? _onlineQueueIndex >= 0 &&
                          _onlineQueueIndex < _onlinePlaybackQueue.length - 1
                    : _currentIndex != null &&
                          _currentIndex! < _queue.length - 1,
              )
            : ExploreOnlinePage(
                config: config,
                recommendations: _exploreFeed.recommendations,
                sessions: _exploreFeed.sessions,
                seedArtists: _exploreFeed.seeds,
                loading: _exploreRecommendationsLoading,
                error: _exploreRecommendationError,
                onRefresh: () =>
                    unawaited(_loadExploreRecommendations(refresh: true)),
                onPlay: (recommendation) =>
                    unawaited(_playExploreRecommendation(recommendation)),
              ),
      'Tu música' => MusicPage(config: config),
      'Favoritos' => FavoritesPage(config: config),
      'Carpetas' => MiddleContentPanel(
        section: _section,
        config: config,
        showHeader: false,
        body: _foldersPanel(),
      ),
      'Álbumes' => AlbumsPage(
        config: config,
        tracks: _tracks,
        loading: _loading,
        compact: compact,
        currentTrackPath: _currentLocalTrack?.path,
        isPlaying: _player.playing,
        favoritePaths: _favorites,
        onToggleFavorite: (track) => unawaited(_toggleFavorite(track)),
        onAddToPlaylist: (track) => unawaited(_addToPlaylist(track)),
        onPlayTracks: _playCollection,
      ),
      'Artistas' => ArtistsPage(
        config: config,
        tracks: _tracks,
        loading: _loading,
        compact: compact,
        currentTrackPath: _currentLocalTrack?.path,
        isPlaying: _player.playing,
        favoritePaths: _favorites,
        onToggleFavorite: (track) => unawaited(_toggleFavorite(track)),
        onAddToPlaylist: (track) => unawaited(_addToPlaylist(track)),
        featuredArtists: _worldArtists.isNotEmpty
            ? _worldArtists
                  .take(12)
                  .map((artist) => artist.name)
                  .toList(growable: false)
            : _worldTop
                  .map((track) => track.artist.trim())
                  .where((artist) => artist.isNotEmpty)
                  .toSet()
                  .take(12)
                  .toList(growable: false),
        worldArtists: _worldArtists,
        trendingTracks: _worldTop,
        preferredArtists: _preferredArtists,
        recentlyHeardTrackKeys: _recentlyHeardTrackKeys,
        trackPlayCounts: _trackPlayCounts,
        onPlayTracks: _playCollection,
        onPlayArtistStation: _playArtistStation,
        onPlayArtistSong: _playArtistDiscoveryTrack,
        onPlayChartTrack: (track, queue) async {
          await _playHomeChartTrack(track, chart: queue, session: 'world');
        },
        onAddChartToPlaylist: _addChartTrackToPlaylist,
        onToggleChartFavorite: _toggleChartFavorite,
      ),
      'Playlists' => PlaylistsPage(
        config: config,
        tracks: _tracks,
        playlists: _playlists,
        favoritePaths: _favorites,
        currentTrackPath: _currentLocalTrack?.path,
        isPlaying: _player.playing,
        onPlayTracks: _playCollection,
        onToggleFavorite: (track) => unawaited(_toggleFavorite(track)),
        onAddTracksToPlaylist: _addTracksToPlaylist,
        onRemoveTrack: (name, track) =>
            unawaited(_removeTrackFromPlaylist(name, track.path)),
      ),
      _ => MiddleContentPanel(section: _section, config: config),
    };
  }

  Widget _onlineSearchPanel() {
    if (_query.trim().isEmpty) {
      return _notAvailable(
        'Busca música online',
        'Escribe el nombre de una canción o artista. Pulsa el icono de reproducción para escucharla en SoundNeed.',
      );
    }
    if (_onlineSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _cyan),
              SizedBox(height: 14),
              Text(
                'Buscando música online…',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (_onlineError != null) {
      return _notAvailable(
        _onlineError!,
        'Revisa la conexión a internet o cambia la búsqueda.',
      );
    }
    if (_onlineResults.isEmpty) return const SizedBox.shrink();
    return OnlineSearchResults(
      results: _onlineResults
          .map(
            (track) => OnlineSearchResult(
              videoId: track.videoId,
              title: track.title,
              artist: track.artist,
              thumbnail: track.thumbnail,
              durationSeconds: track.durationSeconds,
            ),
          )
          .toList(growable: false),
      playingVideoId: _playingOnlineTrack?.videoId,
      isPlaying: _player.playing,
      loadingVideoId: _onlinePlaybackLoading
          ? _playingOnlineTrack?.videoId
          : null,
      onPlay: (index) => unawaited(
        _playOnlineTrack(
          _onlineResults[index],
          queue: _onlineResults,
          queueIndex: index,
        ),
      ),
      onAddToPlaylist: (index) =>
          unawaited(_addOnlineToPlaylist(_onlineResults[index])),
    );
  }

  Widget _searchResultsPanel(List<Track> localTracks, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (localTracks.isNotEmpty) _trackTable(localTracks, compact),
      if (localTracks.isNotEmpty) const SizedBox(height: 24),
      _onlineSearchPanel(),
    ],
  );

  Widget _queuePanel() => Material(
    color: _raised,
    elevation: 14,
    borderRadius: BorderRadius.circular(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Cola de reproducción',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${_queue.length}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              IconButton(
                tooltip: 'Cerrar cola',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _queueOpen = false),
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: .07)),
        Expanded(
          child: _queue.isEmpty
              ? const Center(
                  child: Text(
                    'La cola está vacía',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: _queue.length,
                  itemBuilder: (context, index) {
                    final track = _tracks
                        .where((item) => item.path == _queue[index])
                        .firstOrNull;
                    if (track == null) return const SizedBox.shrink();
                    final selected = index == _currentIndex;
                    return ListTile(
                      dense: true,
                      onTap: () => _player.seek(Duration.zero, index: index),
                      leading: _cover(track, 34),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? _cyan : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                      trailing: selected
                          ? const Icon(Icons.volume_up, size: 15, color: _cyan)
                          : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 26),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .05)),
    ),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.library_music_outlined,
            color: _cyan,
            size: 28,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _query.isNotEmpty
              ? 'No encontramos coincidencias'
              : _section == 'Favoritos'
              ? 'Aún no tienes favoritos'
              : _section == 'Playlists' && _playlistView != null
              ? 'Esta playlist está vacía'
              : 'Empieza con tu música',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _query.isNotEmpty ? 'Prueba con otro nombre de canción o artista.' : 'Importa archivos o una carpeta para crear tu biblioteca local.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        if (_query.isEmpty && _section != 'Favoritos') ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _importFiles,
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Elegir canciones'),
              ),
              FilledButton.tonalIcon(
                onPressed: _importFolder,
                icon: const SoundNeedSvgIcon('folder', size: 18, color: _cyan),
                label: const Text('Elegir carpeta'),
              ),
              if (_section == 'Playlists')
                OutlinedButton.icon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear playlist'),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _trackTable(
    List<Track> tracks,
    bool compact, {
    bool neutralHome = false,
  }) {
    final plainMusicList = _section == 'Tu música';
    final table = Column(
      children: [
        if (!plainMusicList) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 20,
              14,
              compact ? 14 : 20,
              10,
            ),
            child: Row(
              children: [
                const SizedBox(width: 34),
                const Expanded(
                  flex: 5,
                  child: Text(
                    'TÍTULO',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!compact)
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'ÁLBUM',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 42),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: neutralHome ? .08 : .05),
          ),
        ],
        ...List.generate(
          tracks.length,
          (index) => _trackRow(
            tracks[index],
            index,
            compact,
            neutralHome: neutralHome,
            plainMusicList: plainMusicList,
          ),
        ),
      ],
    );
    if (plainMusicList) return table;
    return Container(
      decoration: BoxDecoration(
        color: neutralHome
            ? const Color(0xFF111111)
            : _panel.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: neutralHome ? .09 : .045),
        ),
      ),
      child: table,
    );
  }

  Widget _trackRow(
    Track track,
    int index,
    bool compact, {
    bool neutralHome = false,
    bool plainMusicList = false,
  }) {
    final playing =
        _currentIndex != null &&
        _currentIndex! < _queue.length &&
        _queue[_currentIndex!] == track.path &&
        (_usingMediaKitForLocalAudio
            ? _localAudioFallback.state.playing
            : _player.playing);
    return InkWell(
      onTap: () => _playTrack(track),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 20,
          plainMusicList ? 12 : 9,
          compact ? 7 : 14,
          plainMusicList ? 12 : 9,
        ),
        child: Row(
          children: [
            if (!plainMusicList)
              SizedBox(
                width: 34,
                child: Semantics(
                  label: 'Reproducir',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _playTrack(track),
                    icon: Icon(
                      playing
                          ? Icons.equalizer_rounded
                          : Icons.play_arrow_rounded,
                      color: playing
                          ? (neutralHome
                                ? const Color(0xFFF4F3EF)
                                : (plainMusicList
                                      ? _appPalette.primary
                                      : _cyan))
                          : _muted,
                      size: 19,
                    ),
                  ),
                ),
              ),
            _cover(track, plainMusicList ? 56 : 42, neutralHome: neutralHome),
            SizedBox(width: plainMusicList ? 15 : 12),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: plainMusicList ? 14 : 12,
                      color: playing && !neutralHome
                          ? (plainMusicList ? _appPalette.primary : _cyan)
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _muted,
                      fontSize: plainMusicList ? 12 : 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!compact && !plainMusicList)
              Expanded(
                flex: 3,
                child: Text(
                  track.album.isEmpty ? '—' : track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            SizedBox(
              width: 48,
              child: Text(
                _time(
                  track.durationMs == null
                      ? null
                      : Duration(milliseconds: track.durationMs!),
                ),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _muted,
                  fontSize: plainMusicList ? 11 : 10,
                ),
              ),
            ),
            Semantics(
              label: 'Más opciones',
              child: TooltipVisibility(
                visible: false,
                child: PopupMenuButton<String>(
                  iconSize: 17,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'favorite') _toggleFavorite(track);
                    if (value == 'playlist') _addToPlaylist(track);
                    if (value == 'removeFromPlaylist') {
                      _removeFromCurrentPlaylist(track.path);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(
                        _favorites.contains(track.path)
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'playlist',
                      child: Text('Añadir a playlist'),
                    ),
                    if (_section == 'Playlists' && _playlistView != null)
                      const PopupMenuItem(
                        value: 'removeFromPlaylist',
                        child: Text('Quitar de esta playlist'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(Track track, double size, {bool neutralHome = false}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(size * .2),
        child: SizedBox(
          width: size,
          height: size,
          child: track.coverPath != null && File(track.coverPath!).existsSync()
              ? Image.file(
                  File(track.coverPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _coverPlaceholder(size, neutralHome: neutralHome),
                )
              : _coverPlaceholder(size, neutralHome: neutralHome),
        ),
      );

  Widget _coverPlaceholder(double size, {bool neutralHome = false}) =>
      Container(
        color: neutralHome ? const Color(0xFF242424) : _raised,
        child: Icon(
          Icons.music_note_rounded,
          color: neutralHome
              ? Colors.white.withValues(alpha: .7)
              : _cyan.withValues(alpha: .75),
          size: size * .48,
        ),
      );

  Widget _miniPlayer(Track? track, bool compact) {
    final onlineTrack = _playingOnlineTrack;
    final hasTrack = track != null || onlineTrack != null;
    final coverSize = compact ? 38.0 : 50.0;
    final coverPath = track?.coverPath;
    final coverFile = coverPath == null ? null : File(coverPath);
    final ImageProvider? artworkProvider =
        coverFile != null && coverFile.existsSync()
        ? FileImage(coverFile)
        : onlineTrack != null
        ? NetworkImage(onlineTrack.thumbnail)
        : null;
    final cover = track != null
        ? _cover(track, coverSize)
        : onlineTrack != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(coverSize * .2),
            child: SizedBox(
              width: coverSize,
              height: coverSize,
              child: Image.network(
                onlineTrack.thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _coverPlaceholder(coverSize),
              ),
            ),
          )
        : Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              color: _raised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note, color: _muted),
          );

    return ValueListenableBuilder<Duration>(
      valueListenable: _position,
      builder: (context, position, child) => MiniPlayer(
        compact: compact,
        hasTrack: hasTrack,
        title: track?.title ?? onlineTrack?.title ?? 'Elige una canción',
        artist:
            track?.artist ?? onlineTrack?.artist ?? 'Tu biblioteca te espera',
        cover: cover,
        artworkProvider: artworkProvider,
        isFavorite: track != null && _favorites.contains(track.path),
        onToggleFavorite: track == null
            ? null
            : () => unawaited(_toggleFavorite(track)),
        // The extracted audio is the playback source of truth. The video may
        // pause or end independently and must not make the mini player report
        // that the song has stopped.
        playingStream: _usingMediaKitForLocalAudio
            ? _localAudioFallback.stream.playing
            : _audioPlayingStream,
        initialPlaying: _usingMediaKitForLocalAudio
            ? _localAudioFallback.state.playing
            : _player.playing,
        loading: _onlinePlaybackLoading,
        onTogglePlayback: (playing) => hasTrack
            ? unawaited(_toggleMiniPlayerPlayback(playing))
            : unawaited(_importFolder()),
        shuffleEnabled: _usingMediaKitForLocalAudio
            ? _localAudioFallback.state.shuffle
            : _player.shuffleModeEnabled,
        onToggleShuffle: onlineTrack == null
            ? () async {
                if (_usingMediaKitForLocalAudio) {
                  await _localAudioFallback.setShuffle(
                    !_localAudioFallback.state.shuffle,
                  );
                } else {
                  await _player.setShuffleModeEnabled(
                    !_player.shuffleModeEnabled,
                  );
                }
                if (mounted) setState(() {});
              }
            : null,
        loopEnabled: _loopEnabled,
        onToggleLoop: () {
          final enabled = !_loopEnabled;
          setState(() => _loopEnabled = enabled);
          if (_usingMediaKitForLocalAudio) {
            unawaited(
              _localAudioFallback.setPlaylistMode(
                enabled ? PlaylistMode.loop : PlaylistMode.none,
              ),
            );
          } else {
            unawaited(
              _player.setLoopMode(enabled ? LoopMode.all : LoopMode.off),
            );
          }
        },
        onPrevious: onlineTrack != null
            ? (_onlineQueueIndex > 0
                  ? () => unawaited(_skipMiniPlayerTrack(-1))
                  : null)
            : (_queue.isEmpty
                  ? null
                  : () => unawaited(_skipMiniPlayerTrack(-1))),
        onNext: onlineTrack != null
            ? (_onlineQueueIndex >= 0 &&
                      _onlineQueueIndex < _onlinePlaybackQueue.length - 1
                  ? () => unawaited(_skipMiniPlayerTrack(1))
                  : null)
            : (_queue.isEmpty
                  ? null
                  : () => unawaited(_skipMiniPlayerTrack(1))),
        position: position,
        duration: _duration,
        positionLabel: _time(position),
        durationLabel: _time(_duration),
        onSeek: !hasTrack || _duration == null
            ? null
            : (position) => unawaited(_seekMiniPlayer(position)),
        volume: _volume,
        onVolumeChanged: (value) {
          setState(() => _volume = value);
          if (_usingMediaKitForLocalAudio) {
            unawaited(_localAudioFallback.setVolume(value * 100));
          } else {
            unawaited(_player.setVolume(value));
          }
        },
        queueOpen: _queueOpen,
        onToggleQueue: () => setState(() => _queueOpen = !_queueOpen),
        windowMaximized: _windowMaximized,
        onToggleWindowSize: () => unawaited(_toggleWindowMaximize()),
        panelColor: _panel,
        accentColor: _cyan,
        mutedColor: _muted,
      ),
    );
  }

  Widget _nowPlayingPanel(Track? track) {
    final onlineTrack = _playingOnlineTrack;
    const artworkSize = 270.0;
    final videoReadyForCurrentTrack =
        _videoMode &&
        !_videoPreviewUnavailable &&
        _videoReadyTrackKey == _videoTrackKey(track, onlineTrack);
    final artwork = _videoMode
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: RepaintBoundary(
              child: media_video.Video(
                controller: _videoController,
                fit: BoxFit.contain,
                controls: media_video.NoVideoControls,
              ),
            ),
          )
        : track != null
        ? _cover(track, artworkSize)
        : onlineTrack != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              onlineTrack.thumbnail,
              width: artworkSize,
              height: artworkSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _coverPlaceholder(artworkSize),
            ),
          )
        : _coverPlaceholder(artworkSize);
    return NowPlayingPanel(
      artwork: artwork,
      artworkSize: artworkSize,
      audioPlaying: _player.playing,
      audioActive: !_videoMode,
      onAudioTap: () => unawaited(_switchToAudioMode()),
      videoActive: _videoMode,
      videoLoading: _videoLoading,
      onCollapse: () => setState(() {
        _nowPlayingCollapsed = true;
      }),
      onOpenExplore: _openCurrentTrackInExplore,
      videoEnabled: onlineTrack?.directAudioUrl == null,
      onVideoTap: onlineTrack?.directAudioUrl != null || _videoLoading
          ? null
          : () async {
              // Small delay to let audio stabilize if it just started
              if (_playingOnlineTrack != null && _onlinePlaybackLoading) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
              unawaited(
                _videoMode
                    ? _switchToAudioMode()
                    : _playVideoPreview(track, onlineTrack),
              );
            },
    );
  }

  Future<void> _closeApp() async {
    if (_closing) return;
    _closing = true;
    try {
      final stopPlayers = <Future<void>>[
        _player.stop().timeout(const Duration(seconds: 2)),
        _videoPlayer.stop().timeout(const Duration(seconds: 2)),
      ];
      final localAudioFallback = _localAudioFallbackPlayer;
      if (localAudioFallback != null) {
        stopPlayers.add(
          localAudioFallback.stop().timeout(const Duration(seconds: 2)),
        );
      }
      await Future.wait(stopPlayers);
    } catch (_) {
      // A stalled player should not prevent the native window from closing.
    } finally {
      try {
        await _windowChannel.invokeMethod<void>('close');
      } catch (_) {
        _closing = false;
      }
    }
  }

  Future<void> _switchToAudioMode() async {
    _videoPlaybackRequestId++;
    _videoLoading = false;
    _videoAudioSyncTimer?.cancel();
    _videoAudioSyncTimer = null;
    if (_videoMode) {
      await _videoPlayer.stop();
      if (!mounted) return;
      setState(() => _videoMode = false);
    }
    if (_usingMediaKitForLocalAudio) return;
    await _player.play();
  }

  Future<Duration> _waitForAudioReady() async {
    if (_usingMediaKitForLocalAudio) {
      final player = _localAudioFallback;
      if (!player.state.playing) {
        final started = player.stream.playing
            .firstWhere((playing) => playing)
            .timeout(const Duration(seconds: 8));
        await player.play();
        await started;
      }
      if (player.state.buffering) {
        final ready = player.stream.buffering
            .firstWhere((buffering) => !buffering)
            .timeout(const Duration(seconds: 15));
        if (player.state.buffering) await ready;
      }
      return player.state.position;
    }

    if (_playingOnlineTrack == null) return _player.position;
    if (_player.processingState != ProcessingState.ready) {
      await _player.playerStateStream
          .firstWhere((state) => state.processingState == ProcessingState.ready)
          .timeout(const Duration(seconds: 15));
    }
    if (!_player.playing) {
      final started = _player.playerStateStream
          .firstWhere(
            (state) =>
                state.playing && state.processingState == ProcessingState.ready,
          )
          .timeout(const Duration(seconds: 8));
      await _player.play();
      await started;
    }
    return _player.position;
  }

  String? _videoTrackKey(Track? track, _OnlineTrack? onlineTrack) {
    if (track != null) return 'local:${track.path}';
    if (onlineTrack != null) return 'online:${onlineTrack.videoId}';
    return null;
  }

  Future<void> _playVideoPreview(
    Track? track,
    _OnlineTrack? onlineTrack,
  ) async {
    final requestId = ++_videoPlaybackRequestId;
    final requestedTrackKey = _videoTrackKey(track, onlineTrack);
    if (mounted) {
      setState(() {
        _videoMode = true;
        _videoLoading = true;
        // Never leave the previous song's video visible while resolving this one.
        _videoPreviewUnavailable = true;
        _videoReadyTrackKey = null;
      });
    }
    try {
      await _videoPlayer.stop();
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      // Don't block video startup waiting for audio. Start loading video immediately
      // and sync in background. Only wait briefly for audio to be at least started.
      final audioReadyFuture = _waitForAudioReady().timeout(
        const Duration(seconds: 8),
        onTimeout: () => _usingMediaKitForLocalAudio
            ? _localAudioFallback.state.position
            : _player.position,
      );
      if (!mounted || requestId != _videoPlaybackRequestId) return;

      // Check if audio is actually playing, if not give it a moment to start
      final isAudioPlaying = _usingMediaKitForLocalAudio
          ? _localAudioFallback.state.playing
          : _player.playing;
      if (!isAudioPlaying) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      String? videoId = onlineTrack?.videoId;
      if (videoId == null && track != null) {
        final resolved = await _resolveHomeChartTrack(
          HomeChartTrack(
            id: 'local:${track.path}',
            title: track.title,
            artist: track.artist,
            artworkUrl: '',
            rank: 0,
          ),
        ).timeout(const Duration(seconds: 10));
        videoId = resolved?.videoId;
      }
      if (videoId == null ||
          videoId.isEmpty ||
          videoId.startsWith('chart:') ||
          videoId.startsWith('podcast:')) {
        throw StateError('No hay un video asociado a esta pista.');
      }
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      Uri? selectedVideoUri;
      Object? lastVideoError;
      Future<Uri?> loadVideoUri(String candidateId) async {
        // NewPipe uses a different YouTube extraction path from
        // youtube_explode and can resolve videos rejected by its manifest API.
        try {
          final uri = await _extractNativeNewPipeVideo(candidateId);
          await _writePlaybackLog(
            'NewPipe resolved video stream: $candidateId',
          );
          return uri;
        } catch (error) {
          lastVideoError = error;
          await _writePlaybackLog(
            'NewPipe video extraction failed for $candidateId: $error',
          );
        }

        final clients = <(String, YoutubeApiClient, bool)>[
          ('Android página', YoutubeApiClient.androidSdkless, true),
          ('Android API', YoutubeApiClient.androidSdkless, false),
          ('TV', YoutubeApiClient.tv, false),
          ('iOS', YoutubeApiClient.ios, false),
          ('Android VR', YoutubeApiClient.androidVr, false),
          ('Safari', YoutubeApiClient.safari, false),
        ];
        for (final (name, client, requireWatchPage) in clients) {
          try {
            final manifest = await _youtube.videos.streamsClient
                .getManifest(
                  candidateId,
                  ytClients: [client],
                  requireWatchPage: requireWatchPage,
                )
                .timeout(const Duration(seconds: 18));
            // Prefer a low resolution muxed stream for quick start. If YouTube
            // only exposes DASH video, it is safe because this player is muted.
            final muxed = manifest.muxed;
            if (muxed.isNotEmpty) {
              final efficientMuxed = muxed
                  .where((stream) => stream.videoResolution.height <= 480)
                  .sortByVideoQuality();
              final stream = efficientMuxed.isNotEmpty
                  ? efficientMuxed.first
                  : muxed.sortByVideoQuality().last;
              return stream.url;
            }
            final videoOnly = manifest.videoOnly;
            if (videoOnly.isNotEmpty) {
              final efficientVideo = videoOnly
                  .where((stream) => stream.videoResolution.height <= 480)
                  .sortByVideoQuality();
              final stream = efficientVideo.isNotEmpty
                  ? efficientVideo.first
                  : videoOnly.sortByVideoQuality().last;
              return stream.url;
            }
            lastVideoError = StateError(
              'El cliente $name no ofreció un stream de video.',
            );
          } catch (error) {
            lastVideoError = error;
            await _writePlaybackLog(
              'YouTube video client $name failed for $candidateId: $error',
            );
          }
        }
        return null;
      }

      selectedVideoUri = await loadVideoUri(videoId);

      if (selectedVideoUri == null) {
        final title = onlineTrack?.title ?? track?.title ?? '';
        final artist = onlineTrack?.artist ?? track?.artist ?? '';
        final query = '$title $artist audio oficial'.trim();
        try {
          final alternatives = await _youtube.search
              .search(query)
              .timeout(const Duration(seconds: 12));
          final seenIds = <String>{videoId};
          for (final candidate in alternatives) {
            if (!mounted || requestId != _videoPlaybackRequestId) return;
            if (!seenIds.add(candidate.id.value)) continue;
            final titleScore = _chartTitleMatch(candidate.title, title);
            final artistScore = _chartArtistMatch(
              candidate.title,
              candidate.author,
              artist,
            );
            final confidentMatch =
                (titleScore >= .72 && artistScore >= .25) ||
                (titleScore >= .9 && artistScore == 0);
            if (!confidentMatch ||
                _chartVersionPenalty(candidate.title, title) > 0) {
              if (seenIds.length >= 4) break;
              continue;
            }
            try {
              selectedVideoUri = await loadVideoUri(candidate.id.value);
              if (selectedVideoUri != null) break;
            } catch (error) {
              lastVideoError = error;
            }
            if (seenIds.length >= 4) break;
          }
        } catch (error) {
          lastVideoError = error;
        }
      }
      if (selectedVideoUri == null) {
        await _writePlaybackLog(
          'All video extraction attempts failed for $videoId: $lastVideoError',
        );
        throw StateError('No se pudo obtener un stream de video reproducible.');
      }
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      // The music player remains the audio source; the video player supplies
      // pictures only, so the muxed YouTube audio cannot play over it.
      // Mute before opening so a muxed stream can never leak its audio.
      await _videoPlayer.setVolume(0);
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      // Show loading state before opening to prevent black screen
      setState(() {
        _videoPreviewUnavailable = false;
        _videoReadyTrackKey = requestedTrackKey;
      });
      await _videoPlayer.open(
        Media(
          selectedVideoUri.toString(),
          httpHeaders: {
            'User-Agent': _youtubeAndroidUserAgent,
            'Accept': '*/*',
            'Range': 'bytes=0-',
          },
        ),
        play: false,
      );
      await _videoPlayer.setVolume(0);
      if (!mounted || requestId != _videoPlaybackRequestId) return;
      // Load paused, seek near the running song, then start the video explicitly.
      // This avoids relying on open() autoplay and never restarts the audio.
      try {
        final audioPosition = await audioReadyFuture;
        await _videoPlayer.seek(audioPosition);
        // Start playing immediately to show video to user
        await _videoPlayer.play();
        // Show video as soon as it starts playing, don't wait for perfect sync
        final videoStarted = _videoPlayer.stream.playing
            .firstWhere((playing) => playing)
            .timeout(const Duration(seconds: 6));
        await videoStarted;
        if (!mounted || requestId != _videoPlaybackRequestId) return;
        // Now try to sync in background
        try {
          final firstVideoAdvance = _videoPlayer.stream.position
              .firstWhere(
                (position) =>
                    position >=
                    audioPosition + const Duration(milliseconds: 120),
              )
              .timeout(const Duration(seconds: 6));
          await firstVideoAdvance;
          _startVideoAudioSync();
        } catch (syncError) {
          debugPrint('Sync attempt failed, but video is playing: $syncError');
          // Still start sync timer even if initial sync failed
          _startVideoAudioSync();
        }
      } catch (error, stackTrace) {
        debugPrint('No se pudo iniciar el video: $error');
        debugPrintStack(stackTrace: stackTrace);
        // Even if play fails, show video if it's loaded
        if ((_videoPlayer.state.width ?? 0) > 0 &&
            (_videoPlayer.state.height ?? 0) > 0) {
          _startVideoAudioSync();
        } else {
          setState(() {
            _videoPreviewUnavailable = true;
          });
          _toast('No se pudo iniciar el video: $error');
        }
      }
    } catch (error, stackTrace) {
      if (requestId != _videoPlaybackRequestId) return;
      debugPrint('No se pudo iniciar el modo video: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_videoMode) {
        _videoAudioSyncTimer?.cancel();
        await _videoPlayer.stop();
        // Switch back to audio mode if video completely failed
        if (mounted) {
          setState(() {
            _videoMode = false;
            _videoPreviewUnavailable = true;
          });
        }
      }
      if (mounted) {
        _toast('No se pudo iniciar el video: $error');
      }
    } finally {
      if (mounted && requestId == _videoPlaybackRequestId) {
        setState(() => _videoLoading = false);
      }
    }
  }

  void _startVideoAudioSync() {
    _videoAudioSyncTimer?.cancel();
    _videoAudioSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_videoMode ||
          !_videoPlayer.state.playing ||
          _videoAudioSyncInProgress) {
        return;
      }
      final videoPosition = _videoPlayer.state.position;
      final audioPosition = _usingMediaKitForLocalAudio
          ? _localAudioFallback.state.position
          : _player.position;
      if ((videoPosition - audioPosition).inMilliseconds.abs() < 250) return;
      _videoAudioSyncInProgress = true;
      unawaited(_correctVideoPositionFromAudio(audioPosition));
    });
  }

  Future<void> _correctVideoPositionFromAudio(Duration audioPosition) async {
    try {
      await _videoPlayer.seek(audioPosition);
    } catch (error) {
      debugPrint('Error al ajustar el video al audio: $error');
    } finally {
      _videoAudioSyncInProgress = false;
    }
  }

  Widget _foldersPanel() {
    final importedFolders = _folders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectionHero(
          eyebrow: 'TU BIBLIOTECA',
          title: 'Carpetas',
          description: importedFolders.isEmpty
              ? 'Añade ubicaciones de música para organizar tu colección local.'
              : '${_tracks.length} canciones disponibles desde tus ubicaciones.',
          icon: Icons.folder_copy_rounded,
          accent: _appPalette.primary,
          secondaryAccent: _appPalette.secondary,
          count: importedFolders.length,
          countLabel: importedFolders.length == 1 ? 'carpeta' : 'carpetas',
          action: FilledButton.tonalIcon(
            onPressed: _importFolder,
            icon: Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Añadir carpeta'),
            style: FilledButton.styleFrom(
              backgroundColor: _appPalette.primary.withValues(alpha: .13),
              foregroundColor: _appPalette.primary,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (importedFolders.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _panel.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _appPalette.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    color: _appPalette.primary,
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu biblioteca local está lista para crecer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Al añadir una carpeta, SoundNeed encontrará sus canciones y las reunirá aquí.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: _appPalette.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 11),
              const Text(
                'Ubicaciones importadas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920 ? 2 : 1;
              const gap = 14.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: importedFolders
                    .map((folder) {
                      final separator = Platform.pathSeparator;
                      final prefix = folder.endsWith(separator)
                          ? folder
                          : folder + separator;
                      final count = _tracks
                          .where(
                            (track) => track.path.toLowerCase().startsWith(
                              prefix.toLowerCase(),
                            ),
                          )
                          .length;
                      final parts = folder.split(separator);
                      final name = parts.isEmpty || parts.last.isEmpty
                          ? folder
                          : parts.last;
                      return SizedBox(
                        width: width,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(_panel, _appPalette.primary, .055)!,
                                Color.lerp(
                                  _panel,
                                  _appPalette.secondary,
                                  .035,
                                )!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _appPalette.primary.withValues(
                                    alpha: .09,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _appPalette.primary.withValues(
                                      alpha: .16,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.folder_rounded,
                                  color: _appPalette.primary,
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      folder,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _appPalette.primary.withValues(
                                    alpha: .08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _appPalette.primary.withValues(
                                      alpha: .16,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '$count ${count == 1 ? "canción" : "canciones"}',
                                  style: TextStyle(
                                    color: _appPalette.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _settingsPanel() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Biblioteca local',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '${_folders.length} carpetas importadas · ${_tracks.length} canciones',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _importFolder,
          icon: const SoundNeedSvgIcon('folder', size: 18, color: _cyan),
          label: const Text('Añadir carpeta'),
        ),
        const SizedBox(height: 22),
        const Text(
          'En desarrollo',
          style: TextStyle(color: _cyan, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        const Text(
          'La búsqueda online permite encontrar y reproducir música desde el reproductor. Letras sincronizadas y SoundNeed Connect siguen pendientes.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 20),
        const Text(
          'Diagnóstico de reproducción online',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        const Text(
          'Se registran la resolución del stream y los errores del motor de audio en:',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        FutureBuilder<Directory>(
          future: getApplicationSupportDirectory(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final path =
                '${snapshot.data!.path}${Platform.pathSeparator}logs${Platform.pathSeparator}soundneed.log';
            return SelectableText(
              path,
              style: const TextStyle(color: _cyan, fontSize: 11),
            );
          },
        ),
      ],
    ),
  );

  Widget _notAvailable(String title, String message) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          message,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
}

class _NowPlayingEdgeToggle extends StatefulWidget {
  const _NowPlayingEdgeToggle({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_NowPlayingEdgeToggle> createState() => _NowPlayingEdgeToggleState();
}

class _NowPlayingEdgeToggleState extends State<_NowPlayingEdgeToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Mostrar vista previa',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(24),
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: 48,
              sigmaY: 48,
              tileMode: TileMode.decal,
            ),
            child: ColoredBox(
              color: _hovered
                  ? const Color(0x9925252D)
                  : const Color(0x8817171D),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onPressed,
                  child: Center(
                    child: CustomPaint(
                      size: const Size(42, 88),
                      painter: _OpenPreviewChevronPainter(
                        _hovered
                            ? const Color(0xFFE0E0E8)
                            : const Color(0xFFA8A8B5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _OpenPreviewChevronPainter extends CustomPainter {
  const _OpenPreviewChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .72, 0)
      ..lineTo(size.width * .28, size.height * .5)
      ..lineTo(size.width * .72, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OpenPreviewChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}
