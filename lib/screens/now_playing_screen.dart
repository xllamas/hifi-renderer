import 'package:flutter/material.dart';

import '../renderer_state.dart';

/// The main screen: album art, track information, and the format and
/// resolution actually being sent to the DAC.
///
/// Deliberately sparse. This is meant to be looked at from across a room on a
/// phone that does nothing else, so the track and the format carry the screen
/// and everything operational lives behind the settings button.
class NowPlayingScreen extends StatelessWidget {
  final RendererStatus status;
  final VoidCallback onOpenSettings;

  const NowPlayingScreen({
    super.key,
    required this.status,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: status.hasTrack ? _playing(context) : _idle(context),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings, color: Colors.white38),
                tooltip: 'Settings',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idle(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speaker, size: 64, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 24),
            Text(
              status.rendererName,
              style: const TextStyle(fontSize: 22, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              status.dacConnected
                  ? 'Ready — waiting for a controller'
                  : 'No DAC connected',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
      );

  Widget _playing(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),
          Center(child: _art()),
          const SizedBox(height: 32),
          Text(
            status.title ?? 'Unknown track',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          if (status.artist != null) ...[
            const SizedBox(height: 8),
            Text(
              status.artist!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
          ],
          if (status.album != null) ...[
            const SizedBox(height: 4),
            Text(
              status.album!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Colors.white38),
            ),
          ],
          const SizedBox(height: 28),
          _progress(),
          const SizedBox(height: 24),
          Center(child: _formatBadge()),
          const Spacer(flex: 1),
        ],
      );

  Widget _art() {
    const size = 260.0;
    final uri = status.albumArtUri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? _artPlaceholder()
            : Image.network(
                uri,
                fit: BoxFit.cover,
                // Album art comes from a media server that may be slow, gone,
                // or serving something that is not an image. None of that
                // should disturb the screen.
                errorBuilder: (_, _, _) => _artPlaceholder(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _artPlaceholder(),
              ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
        color: Colors.white10,
        child: Icon(Icons.album, size: 88, color: Colors.white.withValues(alpha: 0.15)),
      );

  Widget _progress() {
    final hasDuration = status.durationSeconds > 0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: hasDuration ? status.progress : null,
            minHeight: 3,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Colors.white54),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(RendererStatus.formatTime(status.positionSeconds),
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
            Text(
              status.isPaused ? 'Paused' : '',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            Text(
              hasDuration ? RendererStatus.formatTime(status.durationSeconds) : '',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  /// Format and resolution, plus whether the samples are reaching the DAC
  /// untouched — the thing this app exists to guarantee.
  Widget _formatBadge() {
    final badge = status.formatBadge;
    if (badge == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (status.bitPerfect) ...[
          const SizedBox(width: 10),
          const Icon(Icons.verified, size: 15, color: Colors.greenAccent),
          const SizedBox(width: 5),
          const Text('bit-perfect',
              style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
        ],
      ],
    );
  }
}
