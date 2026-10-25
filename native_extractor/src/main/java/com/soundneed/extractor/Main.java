package com.soundneed.extractor;

import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.stream.AudioStream;
import org.schabi.newpipe.extractor.stream.StreamExtractor;
import org.schabi.newpipe.extractor.stream.VideoStream;

import java.util.Comparator;
import java.util.List;
import java.util.Locale;

public final class Main {
    private Main() {}

    public static void main(String[] args) {
        final boolean videoMode = args.length == 2 && "video".equals(args[1]);
        if ((args.length != 1 && !videoMode) || !args[0].matches("[A-Za-z0-9_-]{11}")) {
            System.err.println("INVALID_VIDEO_ID: se esperaba un ID de YouTube de 11 caracteres");
            System.exit(2);
            return;
        }

        try {
            NewPipe.init(new WindowsDownloader());
            final String videoId = args[0];
            final StreamExtractor extractor = NewPipe.getService("YouTube")
                    .getStreamExtractor("https://www.youtube.com/watch?v=" + videoId);
            extractor.fetchPage();

            if (videoMode) {
                final List<VideoStream> streams = extractor.getVideoStreams().stream()
                        .filter(VideoStream::isUrl)
                        .filter(stream -> stream.getContent() != null && !stream.getContent().isBlank())
                        .toList();
                final List<VideoStream> efficientStreams = streams.stream()
                        .filter(stream -> stream.getHeight() > 0 && stream.getHeight() <= 480)
                        .toList();
                final VideoStream selected = (efficientStreams.isEmpty() ? streams : efficientStreams)
                        .stream()
                        .min(Comparator.comparingInt(stream -> stream.getHeight() > 0
                                ? Math.abs(stream.getHeight() - 480)
                                : Integer.MAX_VALUE))
                        .orElseThrow(() -> new IllegalStateException(
                                "NewPipe no devolvió streams de video directos"));
                final String url = selected.getContent();
                if (!url.startsWith("https://") && !url.startsWith("http://")) {
                    throw new IllegalStateException("NewPipe devolvió una URL de video inválida");
                }
                // Stdout is a small line protocol consumed by Dart. Never log the signed URL.
                System.out.println(url);
                System.out.println(selected.getHeight());
                return;
            }

            final List<AudioStream> streams = extractor.getAudioStreams().stream()
                    .filter(AudioStream::isUrl)
                    .filter(stream -> stream.getContent() != null && !stream.getContent().isBlank())
                    .sorted(Comparator
                            .comparingInt(Main::codecPriority).reversed()
                            .thenComparing(Comparator.comparingInt(Main::bitrateScore).reversed())
                            .thenComparing(Comparator.comparingInt(AudioStream::getBitrate).reversed()))
                    .toList();

            if (streams.isEmpty()) {
                throw new IllegalStateException("NewPipe no devolvió streams de audio directos");
            }

            final AudioStream selected = streams.get(0);
            final String url = selected.getContent();
            if (!url.startsWith("https://") && !url.startsWith("http://")) {
                throw new IllegalStateException("NewPipe devolvió una URL de audio inválida");
            }

            // Stdout is a small line protocol consumed by Dart. Never log the signed URL.
            System.out.println(url);
            System.out.println(contentType(selected));
            System.out.println(selected.getBitrate());
        } catch (Throwable error) {
            final String message = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
            System.err.println(error.getClass().getSimpleName() + ": " + message);
            System.exit(1);
        }
    }

    private static int codecPriority(AudioStream stream) {
        final String codec = normalizedCodec(stream);
        if (codec.contains("mp4a.40.2")) return 500;
        if (codec.contains("mp4a")) return 450;
        if (codec.contains("audio/mp4")) return 400;
        if (codec.contains("opus")) return 250;
        if (codec.contains("audio/webm")) return 200;
        return 0;
    }

    private static int bitrateScore(AudioStream stream) {
        final int bitrate = stream.getBitrate();
        if (bitrate >= 128_000 && bitrate <= 192_000) return 400;
        if (bitrate >= 192_001 && bitrate <= 256_000) return 350;
        if (bitrate >= 96_000 && bitrate <= 127_999) return 300;
        if (bitrate >= 256_001 && bitrate <= 320_000) return 250;
        if (bitrate > 320_000) return 150;
        if (bitrate > 0) return 100;
        return 0;
    }

    private static String normalizedCodec(AudioStream stream) {
        final String codec = stream.getCodec();
        return codec == null ? "" : codec.toLowerCase(Locale.ROOT).trim();
    }

    private static String contentType(AudioStream stream) {
        final String codec = normalizedCodec(stream);
        if (codec.contains("mp4a.40.5")) return "audio/mp4; codecs=\"mp4a.40.5\"";
        if (codec.contains("mp4a") || codec.contains("aac")) return "audio/mp4; codecs=\"mp4a.40.2\"";
        if (codec.contains("opus")) return "audio/webm; codecs=\"opus\"";
        if (codec.contains("vorbis")) return "audio/webm; codecs=\"vorbis\"";
        if (codec.contains("mpeg") || codec.contains("mp3")) return "audio/mpeg";
        return "audio/mp4; codecs=\"mp4a.40.2\"";
    }
}
