import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';

/// A bridge to the native Android VPN service
class AndroidVPNBridge {
  // Singleton pattern
  static final AndroidVPNBridge _instance = AndroidVPNBridge._internal();
  factory AndroidVPNBridge() => _instance;
  AndroidVPNBridge._internal();

  // Method channel for communication with native code
  static const MethodChannel _methodChannel = MethodChannel('${AppConstants.packageName}/vpn');
  static const EventChannel _eventChannel = EventChannel('${AppConstants.packageName}/vpn_events');

  // VPN status stream
  StreamSubscription? _vpnStatusSubscription;
  final _statusController = StreamController<int>.broadcast();
  Stream<int> get status => _statusController.stream;

  // Prepare the VPN service
  Future<bool> prepare() async {
    if (!Platform.isAndroid) return true; // Only applies to Android
    
    try {
      LoggerService.info('Preparing Android VPN service');
      final result = await _methodChannel.invokeMethod<bool>('prepare');
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to prepare Android VPN service', e);
      return false;
    }
  }

  // Start the VPN service
  Future<bool> start(Map<String, dynamic> config) async {
    if (!Platform.isAndroid) return false; // Only applies to Android
    
    try {
      LoggerService.info('Starting Android VPN service');
      
      // Ensure the service is prepared
      final prepared = await prepare();
      if (!prepared) {
        LoggerService.error('VPN service not prepared');
        return false;
      }
      
      // Start listening for status updates
      _startStatusListener();
      
      // Start the VPN service
      final result = await _methodChannel.invokeMethod<bool>('start', config);
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to start Android VPN service', e);
      return false;
    }
  }

  // Stop the VPN service
  Future<bool> stop() async {
    if (!Platform.isAndroid) return true; // Only applies to Android
    
    try {
      LoggerService.info('Stopping Android VPN service');
      final result = await _methodChannel.invokeMethod<bool>('stop');
      
      // Stop listening for status updates
      _stopStatusListener();
      
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to stop Android VPN service', e);
      return false;
    }
  }

  // Check if the VPN service is running
  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false; // Only applies to Android
    
    try {
      final result = await _methodChannel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to check if Android VPN service is running', e);
      return false;
    }
  }

  // Set up a listener for VPN status updates
  void _startStatusListener() {
    if (_vpnStatusSubscription != null) return;
    
    LoggerService.info('Starting Android VPN status listener');
    
    _vpnStatusSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final status = event as int;
        LoggerService.info('Android VPN status update: $status');
        _statusController.add(status);
      },
      onError: (dynamic error) {
        LoggerService.error('Android VPN status listener error', error);
      },
    );
  }

  // Stop listening for VPN status updates
  void _stopStatusListener() {
    LoggerService.info('Stopping Android VPN status listener');
    _vpnStatusSubscription?.cancel();
    _vpnStatusSubscription = null;
  }

  // Get traffic statistics
  Future<Map<String, dynamic>> getTrafficStats() async {
    if (!Platform.isAndroid) {
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'connectionTime': 0,
      };
    }
    
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getTrafficStats');
      
      if (result != null) {
        return {
          'downloadedBytes': result['downloadedBytes'] ?? 0,
          'uploadedBytes': result['uploadedBytes'] ?? 0,
          'connectionTime': result['connectionTime'] ?? 0,
        };
      }
      
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'connectionTime': 0,
      };
    } catch (e) {
      LoggerService.error('Failed to get Android VPN traffic stats', e);
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'connectionTime': 0,
      };
    }
  }

  // Add an app to the split tunneling list (for Android)
  Future<bool> addAppToSplitTunnel(String packageName) async {
    if (!Platform.isAndroid) return false;
    
    try {
      LoggerService.info('Adding app to Android VPN split tunnel: $packageName');
      final result = await _methodChannel.invokeMethod<bool>(
          'addAppToSplitTunnel', {'packageName': packageName});
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to add app to Android VPN split tunnel', e);
      return false;
    }
  }

  // Remove an app from the split tunneling list (for Android)
  Future<bool> removeAppFromSplitTunnel(String packageName) async {
    if (!Platform.isAndroid) return false;
    
    try {
      LoggerService.info('Removing app from Android VPN split tunnel: $packageName');
      final result = await _methodChannel.invokeMethod<bool>(
          'removeAppFromSplitTunnel', {'packageName': packageName});
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to remove app from Android VPN split tunnel', e);
      return false;
    }
  }

  // Get the list of apps in the split tunneling list (for Android)
  Future<List<String>> getSplitTunnelApps() async {
    if (!Platform.isAndroid) return [];
    
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('getSplitTunnelApps');
      
      if (result != null) {
        return result.map((app) => app.toString()).toList();
      }
      
      return [];
    } catch (e) {
      LoggerService.error('Failed to get Android VPN split tunnel apps', e);
      return [];
    }
  }

  // Set the split tunneling mode (for Android)
  // mode: 0 = Off, 1 = Exclude apps (tunnel all except specified)
  // mode: 2 = Include apps (tunnel only specified)
  Future<bool> setSplitTunnelMode(int mode) async {
    if (!Platform.isAndroid) return false;
    
    try {
      LoggerService.info('Setting Android VPN split tunnel mode: $mode');
      final result = await _methodChannel.invokeMethod<bool>(
          'setSplitTunnelMode', {'mode': mode});
      return result ?? false;
    } catch (e) {
      LoggerService.error('Failed to set Android VPN split tunnel mode', e);
      return false;
    }
  }

  // Cleanup resources
  void dispose() {
    _stopStatusListener();
    _statusController.close();
  }
}