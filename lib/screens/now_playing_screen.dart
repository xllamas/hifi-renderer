import 'package:flutter/material.dart';

import '../renderer_state.dart';

/// The main screen: album art, track information, and the format and
/// resolution actually being sent to the DAC.
///
/// Deliberately sparse. This is meant to be read from across a room on a phone
/// that does nothing else, so the art, the track and the format carry the
/// screen and everything operational lives behind the settings button.
///
/// Two layouts: portrait stacks art above the details, landscape puts art on
/// the left and everything else on the right, which is the sensible shape when
/// the phone is docked on its side.
class NowPlayingScreen extends StatelessWidget {
  final RendererStatus status;
  final VoidCallback onOpenSettings;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<int> onVolumeChanged;

  const NowPlayingScreen({
    super.key,
    required this.status,
    required this.onOpenSettings,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final landscape = constraints.maxWidth > constraints.maxHeight;
                if (!status.hasTrack) return _idle(context);
                return landscape
                    ? _landscape(context, constraints)
                    : _portrait(context, constraints);
              },
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

  bool get _hasProblem => status.lastError != null && !status.isPlaying;

  /// Why the last track did not play.
  ///
  /// A refusal that shows nothing is indistinguishable from the app being
  /// broken -- which is exactly what a track silently failing to start looks
  /// like from across the room. So the sentence that says what happened is
  /// sized to be read from there, and the engine's own wording sits beneath it
  /// in the size it deserves: there for whoever walks over, and not competing
  /// with the part that is actually legible at a distance.
  ///
  /// It takes space in the layout rather than floating over it. As an overlay
  /// it landed on top of the format badge, so the two things the screen was
  /// meant to be answering -- what is playing, and why nothing is -- obscured
  /// each other.
  Widget _problem() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 20, color: Colors.amberAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.lastError!,
                    // Bounded so an unusually long headline cannot push the
                    // banner off the screen again. Three lines is enough for
                    // every message Problem composes.
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: Colors.white),
                  ),
                  if (status.lastErrorDetail != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      status.lastErrorDetail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _idle(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speaker, size: 64, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 24),
            Text(status.rendererName,
                style: const TextStyle(fontSize: 22, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              status.dacConnected
                  ? 'Ready — waiting for a controller'
                  : 'No DAC connected',
              style: const TextStyle(color: Colors.white38),
            ),
            if (status.dacConnected && status.dacName != null) ...[
              const SizedBox(height: 18),
              _outputDevice(),
            ],
            // A refusal that emptied the queue leaves nothing playing, and the
            // reason has to survive that or the screen goes back to looking
            // idle as though nothing had been asked of it.
            if (_hasProblem) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _edge * 2),
                child: _problem(),
              ),
            ],
          ],
        ),
      );

  // Half the previous edge margin, so the art can be noticeably larger.
  static const _edge = 14.0;

  Widget _portrait(BuildContext context, BoxConstraints c) {
    // Art fills the width less the margins, capped so it cannot crowd out the
    // text and controls on short screens -- and capped harder when the problem
    // banner is up, because that is a third block of text competing for the
    // same column. Without this the banner overflowed the bottom of the screen
    // and Flutter drew its stripes over the very message the user needed.
    final art = (c.maxWidth - _edge * 2)
        .clamp(0.0, c.maxHeight * (_hasProblem ? 0.34 : 0.52));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _edge, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(child: _art(art)),
          const SizedBox(height: 28),
          _titleBlock(centred: true),
          const SizedBox(height: 22),
          _progress(),
          const SizedBox(height: 12),
          _controls(centred: true),
          if (status.canControlVolume) ...[
            const SizedBox(height: 4),
            _volume(),
          ],
          const SizedBox(height: 16),
          Center(child: _formatBadge()),
          if (status.usingSystemAudio) ...[
            const SizedBox(height: 10),
            Center(child: _systemOutput()),
          ] else if (status.dacName != null) ...[
            const SizedBox(height: 10),
            Center(child: _outputDevice()),
          ],
          if (_hasProblem) ...[
            const SizedBox(height: 18),
            _problem(),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _landscape(BuildContext context, BoxConstraints c) {
    final art = (c.maxHeight - _edge * 2)
        .clamp(0.0, c.maxWidth * (_hasProblem ? 0.34 : 0.45));
    return Padding(
      padding: const EdgeInsets.all(_edge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _art(art),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleBlock(centred: false),
                const SizedBox(height: 20),
                _progress(),
                const SizedBox(height: 8),
                _controls(centred: false),
                if (status.canControlVolume) ...[
                  const SizedBox(height: 4),
                  _volume(),
                ],
                const SizedBox(height: 14),
                _formatBadge(),
                if (status.usingSystemAudio) ...[
                  const SizedBox(height: 10),
                  _systemOutput(),
                ] else if (status.dacName != null) ...[
                  const SizedBox(height: 10),
                  _outputDevice(),
                ],
                if (_hasProblem) ...[
                  const SizedBox(height: 16),
                  _problem(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleBlock({required bool centred}) {
    final align = centred ? TextAlign.center : TextAlign.start;
    final cross = centred ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          status.displayTitle,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        if (status.artist != null) ...[
          const SizedBox(height: 6),
          Text(status.artist!,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, color: Colors.white70)),
        ],
        if (status.album != null) ...[
          const SizedBox(height: 3),
          Text(status.album!,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: Colors.white38)),
        ],
      ],
    );
  }

  Widget _art(double size) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: status.albumArtUri == null
              ? _artPlaceholder()
              : Image.network(
                  status.albumArtUri!,
                  fit: BoxFit.cover,
                  // Art comes from a media server that may be slow, gone, or
                  // serving something that is not an image. None of that should
                  // disturb the screen.
                  errorBuilder: (_, _, _) => _artPlaceholder(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : _artPlaceholder(),
                ),
        ),
      );

  Widget _artPlaceholder() => Container(
        color: Colors.white10,
        child: Icon(Icons.album,
            size: 88, color: Colors.white.withValues(alpha: 0.15)),
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
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(RendererStatus.formatTime(status.positionSeconds),
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
            Text(
              hasDuration ? RendererStatus.formatTime(status.durationSeconds) : '',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  /// Play/pause, with skip either side when the renderer holds the playlist.
  ///
  /// The skip buttons appear only for a local playlist, and that restraint is
  /// the point: with a DLNA source the renderer is told one track at a time and
  /// has no idea what comes next, so a next button there would either do
  /// nothing or do something surprising. They are disabled rather than hidden
  /// at the ends of a list — the shape of the controls should not change under
  /// someone's thumb as a playlist advances — unless repeat is on, in which
  /// case both ends stay reachable.
  Widget _controls({required bool centred}) => Row(
        mainAxisAlignment:
            centred ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (status.hasLocalPlaylist) ...[
            IconButton(
              onPressed: status.canGoPrevious ? onPrevious : null,
              iconSize: 30,
              icon: const Icon(Icons.skip_previous),
              color: Colors.white70,
              disabledColor: Colors.white24,
              tooltip: 'Previous track',
            ),
            const SizedBox(width: 8),
          ],
          IconButton.filledTonal(
            onPressed: onPlayPause,
            iconSize: 34,
            padding: const EdgeInsets.all(12),
            icon: Icon(status.isPlaying ? Icons.pause : Icons.play_arrow),
            tooltip: status.isPlaying ? 'Pause' : 'Play',
          ),
          if (status.hasLocalPlaylist) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: status.canGoNext ? onNext : null,
              iconSize: 30,
              icon: const Icon(Icons.skip_next),
              color: Colors.white70,
              disabledColor: Colors.white24,
              tooltip: 'Next track',
            ),
          ],
        ],
      );

  /// Only shown when the DAC actually accepts volume changes. A slider that
  /// silently does nothing is worse than no slider — which is exactly the
  /// confusion this app exists to spare people.
  Widget _volume() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.volume_down, size: 18, color: Colors.white38),
              Expanded(
                child: Slider(
                  value: status.dacVolume.clamp(0, 100).toDouble(),
                  max: 100,
                  onChanged: (v) => onVolumeChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text('${status.dacVolume}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            ],
          ),
          // The DAC takes a volume but always reports its maximum back, so its
          // own knob cannot be followed. Saying so is better than showing a
          // number that quietly stops being true.
          if (status.volumeIsWriteOnly)
            const Padding(
              padding: EdgeInsets.only(left: 26, right: 34),
              child: Text(
                'This DAC does not report its volume back, so this shows the '
                'last value sent from here.',
                style: TextStyle(fontSize: 11, color: Colors.white30),
              ),
            ),
        ],
      );

  /// Where the audio is going when there is no DAC: the phone's own output,
  /// with what that costs stated rather than implied.
  Widget _systemOutput() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_android, size: 14, color: Colors.amberAccent),
          const SizedBox(width: 6),
          const Text('Phone speaker or headphones — resampled by Android',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      );

  /// Where the audio is going. On a phone that may have several USB devices
  /// attached -- a hub, an Ethernet adapter, more than one DAC -- naming the
  /// output is the difference between trusting the screen and guessing.
  Widget _outputDevice() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.usb, size: 14, color: Colors.white30),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              status.dacName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
          if (status.dacCount > 1) ...[
            const SizedBox(width: 6),
            Text('(1 of ${status.dacCount})',
                style: const TextStyle(fontSize: 11, color: Colors.white24)),
          ],
        ],
      );

  /// Format and resolution, plus whether samples are reaching the DAC
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
          child: Text(badge,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.white70,
                letterSpacing: 0.5,
              )),
        ),
        if (status.bitPerfect) ...[
          const SizedBox(width: 10),
          const Icon(Icons.verified, size: 15, color: Colors.greenAccent),
          const SizedBox(width: 5),
          const Text('bit-perfect',
              style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
        ]
        // Never leave this ambiguous. Saying nothing would let the fallback
        // pass for the real thing, and the difference between them is the
        // reason the app exists.
        else if (status.usingSystemAudio) ...[
          const SizedBox(width: 10),
          const Icon(Icons.warning_amber_outlined,
              size: 15, color: Colors.amberAccent),
          const SizedBox(width: 5),
          const Text('system audio',
              style: TextStyle(fontSize: 12, color: Colors.amberAccent)),
        ]
        // A guest streaming over AirPlay reaches the DAC by the same
        // untouched path as everything else, so the fallback warning would be
        // wrong here — but the sender resampled the audio and applied its own
        // volume before it ever arrived, so the tick would be a lie. It gets
        // its own words, and they name the path so the owner can see at a
        // glance that a guest has the output rather than that something broke.
        else if (status.senderAltered) ...[
          const SizedBox(width: 10),
          const Icon(Icons.cast_connected, size: 15, color: Colors.amberAccent),
          const SizedBox(width: 5),
          const Text('AirPlay · sender resampled',
              style: TextStyle(fontSize: 12, color: Colors.amberAccent)),
        ],
      ],
    );
  }
}
