class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverPath,
    this.durationMs,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final String? coverPath;
  final int? durationMs;

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'coverPath': coverPath,
    'durationMs': durationMs,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    path: json['path'] as String,
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    album: json['album'] as String? ?? '',
    coverPath: json['coverPath'] as String?,
    durationMs: json['durationMs'] as int?,
  );
}
