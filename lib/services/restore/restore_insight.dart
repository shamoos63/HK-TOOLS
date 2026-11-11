/// Turns idevicerestore's raw output into what a person needs to see:
/// one overall percentage, the step in plain words, and a clear explanation
/// when a restore fails.
library;

import '../../domain/entities/ios_device.dart';
import '../device/device_parsers.dart';

/// Plain-language name and description of a restore step, plus its share of
/// the whole restore (rough time weights from typical restores).
class StepInfo {
  const StepInfo(this.title, this.description, this.weight);

  final String title;
  final String description;
  final double weight;
}

abstract final class RestoreInsight {
  /// Steps in the order a restore normally passes through them.
  /// (idevicerestore's step numbers are not in time order: images are sent
  /// to the device in Recovery mode before the restore OS prepares it.)
  static const order = [
    RestoreStep.detect,
    RestoreStep.uploadImage,
    RestoreStep.prepare,
    RestoreStep.uploadFilesystem,
    RestoreStep.verifyFilesystem,
    RestoreStep.flashFirmware,
    RestoreStep.flashBaseband,
    RestoreStep.firmwareUpdate,
  ];

  static StepInfo info(RestoreStep s) => switch (s) {
    RestoreStep.detect => const StepInfo(
      'Connecting to the device',
      'Finding the device and checking the firmware fits it.',
      2,
    ),
    RestoreStep.uploadImage => const StepInfo(
      'Starting the restore system',
      'Sending the boot files that put the device into restore mode.',
      6,
    ),
    RestoreStep.prepare => const StepInfo(
      'Preparing the device',
      'Partitioning and erasing storage for the new system.',
      7,
    ),
    RestoreStep.uploadFilesystem => const StepInfo(
      'Installing iOS',
      'Copying the system image to the device. This is the longest step.',
      48,
    ),
    RestoreStep.verifyFilesystem => const StepInfo(
      'Verifying iOS',
      'Checking that the system was written correctly.',
      14,
    ),
    RestoreStep.flashFirmware => const StepInfo(
      'Updating firmware',
      'Writing the boot chain and other low-level firmware.',
      10,
    ),
    RestoreStep.flashBaseband => const StepInfo(
      'Updating the modem',
      'Installing the cellular baseband firmware.',
      8,
    ),
    RestoreStep.firmwareUpdate => const StepInfo(
      'Finishing up',
      'Updating accessories such as Face ID, Touch ID and the display.',
      5,
    ),
  };

  static double get _total => order.fold(0.0, (sum, s) => sum + info(s).weight);

  /// Whole-restore progress, 0–1, for being [fraction] through [step].
  static double overall(RestoreStep? step, double fraction) {
    if (step == null) return 0;
    var done = 0.0;
    for (final s in order) {
      if (s == step) {
        done += info(s).weight * fraction.clamp(0, 1);
        break;
      }
      done += info(s).weight;
    }
    return (done / _total).clamp(0, 0.99);
  }

  /// One-line description of what the tool is doing, from a log line, for
  /// the stretches where it reports no progress numbers (entering Recovery,
  /// asking Apple for a signature, rebooting). `null` = no change.
  static String? activity(String line) {
    final l = line.toLowerCase();
    if (l.startsWith('\$ idevicerestore')) return 'Starting…';
    if (l.contains('extracting') && l.contains('filesystem')) {
      return 'Unpacking the firmware file…';
    }
    if (l.contains('entering recovery mode') ||
        l.contains('enter recovery mode')) {
      return 'Rebooting the device into Recovery mode…';
    }
    if (l.contains('tss') || l.contains('shsh') || l.contains('apticket')) {
      return 'Asking Apple to approve this firmware…';
    }
    if (l.contains('waiting for device to enter restore mode') ||
        l.contains('waiting for device to reconnect') ||
        l.contains('waiting for device')) {
      return 'Waiting for the device to restart…';
    }
    if (l.startsWith('sending ') || l.contains('uploading')) {
      return 'Sending files to the device…';
    }
    if (l.contains('about to restore') || l.contains('starting restore')) {
      return 'Starting the restore…';
    }
    if (l.contains('restore successful') || l == 'done') {
      return 'Restarting the device…';
    }
    return null;
  }

  /// Explains a failed restore from its log.
  static RestoreFailure explain(
    List<RestoreLogEvent> log, {
    bool aborted = false,
  }) {
    final errors = [
      for (final e in log)
        if (e.isError) e.line,
    ];
    final lastError = errors.isEmpty ? null : errors.last;
    if (aborted) {
      return RestoreFailure(
        title: 'The restore was stopped',
        message:
            'You stopped the restore before it finished. If the device now '
            'shows a cable and computer, it is in Recovery mode and needs a '
            'new restore to start again.',
        tips: const [
          'Start the restore again with the same firmware.',
          'Leave the cable connected until it finishes.',
        ],
        detail: lastError,
      );
    }
    // Only the errors and the last lines: earlier, harmless lines mention
    // words like "baseband" on every restore.
    final tail = log.length > 15 ? log.sublist(log.length - 15) : log;
    final text = [
      ...errors,
      for (final e in tail) e.line,
    ].join('\n').toLowerCase();
    bool has(List<String> needles) => needles.any(text.contains);

    for (final rule in _rules) {
      if (has(rule.needles)) {
        return RestoreFailure(
          title: rule.title,
          message: rule.message,
          tips: rule.tips,
          detail: lastError,
        );
      }
    }
    return RestoreFailure(
      title: 'The restore did not finish',
      message:
          'idevicerestore stopped with an error we do not have an explanation '
          'for yet. The technical details below show the last thing it '
          'reported.',
      tips: const [
        'Connect the cable straight to the computer (no hub) and try again.',
        'Put the device in Recovery or DFU mode and restore again.',
        'Download the firmware again if the problem repeats.',
      ],
      detail: lastError,
    );
  }

  static const _rules = [
    _Rule(
      [
        'not being signed',
        "isn't eligible",
        'is not eligible',
        'unable to get shsh',
        'could not get shsh',
        'failed to get shsh',
        'tss request failed',
        'unable to send tss request',
        'error sending tss request',
        'this device isn',
      ],
      'Apple is not approving this firmware',
      'Every restore needs a signature from Apple, and Apple refused one for '
          'this iOS version. Usually it means Apple has stopped signing it, '
          'or this computer could not reach Apple\'s servers.',
      [
        'Pick a firmware marked "Signed" in the IPSW Library.',
        'Check the internet connection and that nothing blocks gs.apple.com.',
      ],
    ),
    _Rule(
      [
        'no space left',
        'not enough space',
        'disk full',
        'failed to extract',
        'unable to extract',
      ],
      'Not enough disk space on this computer',
      'The firmware is unpacked on this computer before it is sent to the '
          'device, and there was not enough free space.',
      [
        'Free up space about as large as the IPSW file and try again.',
        'Empty the restore cache in Settings if a previous restore left one.',
      ],
    ),
    _Rule(
      [
        'ipsw not found',
        'unable to open ipsw',
        'failed to open ipsw',
        'not a valid ipsw',
        'unable to read buildmanifest',
        'failed to read buildmanifest',
        'unable to extract buildmanifest',
        'zip error',
        'corrupt',
      ],
      'The firmware file cannot be read',
      'The IPSW file is missing, incomplete or damaged.',
      [
        'Download the firmware again from the IPSW Library.',
        'Make sure the drive that holds it is still connected.',
      ],
    ),
    _Rule(
      [
        'unable to find a matching build identity',
        'no matching build identity',
        'does not support',
        'not compatible',
        'unable to find a build identity',
      ],
      'This firmware is not for this device',
      'The IPSW was made for a different model, so it cannot be installed.',
      ['Choose firmware that lists this exact model in the IPSW Library.'],
    ),
    _Rule(
      ['baseband', 'bbfw'],
      'The modem firmware could not be installed',
      'iOS was written but the cellular baseband step failed. This can '
          'happen with a hardware fault on the modem or when its firmware is '
          'not signed.',
      [
        'Try the restore again with the latest signed firmware.',
        'If it fails again at the same step, the modem may need repair.',
      ],
    ),
    _Rule(
      [
        'no device found',
        'unable to discover device',
        'device did not reconnect',
        "device didn't reconnect",
        'timeout waiting for device',
        'timed out waiting',
        'lost connection',
        'device disconnected',
        'unable to connect to device',
        'usb error',
        'libusb',
      ],
      'The device lost its connection',
      'The device disconnected or did not come back after restarting. This '
          'is almost always the cable, a USB hub, or the computer going to '
          'sleep.',
      [
        'Use a direct USB cable (ideally an Apple one), not a hub or adapter.',
        'Put the device in Recovery or DFU mode and restore again.',
        'Keep the computer awake until the restore ends.',
      ],
    ),
    _Rule(
      [
        'lockdownd',
        'pairing',
        'could not connect to lockdown',
        'invalid host id',
        'password protected',
      ],
      'The device would not let this computer connect',
      'The device was locked or has not trusted this computer.',
      [
        'Unlock the device and tap "Trust" when asked.',
        'Or put it in Recovery mode, which needs no passcode.',
      ],
    ),
    _Rule(
      ['activation', 'find my'],
      'Activation Lock is blocking the restore',
      'The device is linked to an Apple ID with Find My turned on.',
      [
        'Turn off Find My on the device, or remove it from the owner\'s '
            'Apple ID at icloud.com, then try again.',
      ],
    ),
  ];
}

class _Rule {
  const _Rule(this.needles, this.title, this.message, this.tips);

  final List<String> needles;
  final String title;
  final String message;
  final List<String> tips;
}

/// Why a restore failed, in plain words.
class RestoreFailure {
  const RestoreFailure({
    required this.title,
    required this.message,
    required this.tips,
    this.detail,
  });

  final String title;
  final String message;

  /// Things to try, most likely fix first.
  final List<String> tips;

  /// The tool's own last error line, for reference.
  final String? detail;
}
