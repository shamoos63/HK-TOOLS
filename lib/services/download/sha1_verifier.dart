import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// A running SHA1 computation on a background isolate.
class Sha1Job {
  Sha1Job._(this.result, this._cancel);

  /// Lower-case hex digest.
  final Future<String> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// Hashes multi-GB files off the UI isolate with progress reporting.
class Sha1Verifier {
  static Sha1Job start(
    String path, {
    void Function(double fraction)? onProgress,
  }) {
    final completer = Completer<String>();
    final port = ReceivePort();
    final errorPort = ReceivePort();
    Isolate? isolate;

    void finish() {
      port.close();
      errorPort.close();
    }

    port.listen((message) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is String && !completer.isCompleted) {
        completer.complete(message);
        finish();
      }
    });
    errorPort.listen((message) {
      if (completer.isCompleted) return;
      final list = message as List;
      completer.completeError(
        FileSystemException('SHA1 failed: ${list.first}', path),
      );
      finish();
    });

    Isolate.spawn(_hashEntry, (
      path,
      port.sendPort,
    ), onError: errorPort.sendPort).then(
      (i) => isolate = i,
      onError: (Object e, StackTrace s) {
        if (!completer.isCompleted) completer.completeError(e, s);
        finish();
      },
    );

    return Sha1Job._(completer.future, () {
      isolate?.kill(priority: Isolate.immediate);
      if (!completer.isCompleted) {
        completer.completeError(StateError('SHA1 verification cancelled'));
      }
      finish();
    });
  }

  static Future<void> _hashEntry((String, SendPort) args) async {
    final (path, send) = args;
    final file = File(path);
    final total = await file.length();
    final sink = _DigestSink();
    final input = sha1.startChunkedConversion(sink);
    var read = 0;
    var lastReport = 0;
    const reportEvery = 64 * 1024 * 1024;
    await for (final block in file.openRead()) {
      input.add(block);
      read += block.length;
      if (read - lastReport >= reportEvery) {
        lastReport = read;
        send.send(total == 0 ? 1.0 : read / total);
      }
    }
    input.close();
    send.send(1.0);
    send.send(sink.value.toString());
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
