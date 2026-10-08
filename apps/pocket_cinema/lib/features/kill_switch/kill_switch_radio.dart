import 'package:flutter/services.dart';

const killSwitchPlatformChannel = MethodChannel(
  'com.pocketcinema.app/kill_switch',
);

abstract interface class KillSwitchPreferencesStore {
  Future<String?> load();
  Future<void> save(String value);
}

class PlatformKillSwitchPreferencesStore implements KillSwitchPreferencesStore {
  const PlatformKillSwitchPreferencesStore();

  @override
  Future<String?> load() =>
      killSwitchPlatformChannel.invokeMethod<String>('loadPreferences');

  @override
  Future<void> save(String value) => killSwitchPlatformChannel
      .invokeMethod<void>('savePreferences', {'value': value});
}

class KillSwitchSignal {
  const KillSwitchSignal({
    required this.active,
    required this.sender,
    required this.session,
    required this.revision,
  });
  final bool active;
  final String sender;
  final String session;
  final int revision;
}

abstract interface class KillSwitchRadio {
  Stream<KillSwitchSignal> get signals;
  Future<bool> requestPermissions();
  Future<void> startReceiving();
  Future<void> stopReceiving();
  Future<void> broadcast(bool active);
  Future<void> stopBroadcast();
}

class PlatformKillSwitchRadio implements KillSwitchRadio {
  static const _events = EventChannel(
    'com.pocketcinema.app/kill_switch_events',
  );
  Stream<KillSwitchSignal>? _signals;

  @override
  Stream<KillSwitchSignal> get signals => _signals ??= _events
      .receiveBroadcastStream()
      .where(
        (event) =>
            event is Map &&
            event['active'] is bool &&
            event['sender'] is String &&
            event['session'] is String &&
            event['revision'] is int &&
            (event['revision'] as int) >= 0,
      )
      .map(
        (event) => KillSwitchSignal(
          active: event['active'] as bool,
          sender: event['sender'] as String,
          session: event['session'] as String,
          revision: event['revision'] as int,
        ),
      );

  @override
  Future<bool> requestPermissions() async =>
      await killSwitchPlatformChannel.invokeMethod<bool>(
        'requestPermissions',
      ) ??
      false;
  @override
  Future<void> startReceiving() =>
      killSwitchPlatformChannel.invokeMethod<void>('startReceiving');
  @override
  Future<void> stopReceiving() =>
      killSwitchPlatformChannel.invokeMethod<void>('stopReceiving');
  @override
  Future<void> broadcast(bool active) =>
      killSwitchPlatformChannel.invokeMethod<void>('broadcast', active);
  @override
  Future<void> stopBroadcast() =>
      killSwitchPlatformChannel.invokeMethod<void>('stopBroadcast');
}
