import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

// NumDart gives Array, ArrayComplex & arrayToComplexArray
import 'package:scidart/numdart.dart' as nd;
// SciDart gives fft()
import 'package:scidart/scidart.dart' as sd;

bool kDebugMode = true;

class OmDetectionController {
  OmDetectionController._();
  static final OmDetectionController _instance = OmDetectionController._();
  factory OmDetectionController() {
    return _instance;
  }

  static const _channel = MethodChannel('native_audio');

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture();
  bool isRecording = false;
  double? peakFrequency;
  double? peakMagnitude;
  int omCount = 0;
  bool _verdict = false;
  int? _actualSampleRate;

  Future<void> start(void Function(void Function()) refreshUi) async {
    await _audioCapture.init();
    await _getActualSampleRate();
    await _startCapture(refreshUi, _actualSampleRate!);

    refreshUi(() {});
  }

  void stop(void Function(void Function()) refreshUi) {
    _audioCapture.stop();
    refreshUi(() {
      isRecording = false;
    });
  }

  Future<void> _getActualSampleRate() async {
    try {
      final int rate = await _channel.invokeMethod('getSampleRate');
      _actualSampleRate = rate;
      if (kDebugMode) print('Actual sample rate: $rate Hz');
    } on PlatformException catch (e) {
      _actualSampleRate = 44100;
      if (kDebugMode) print('Error getting sample rate: ${e.message}');
    }
  }

  Future<void> _startCapture(
    void Function(void Function()) refreshUi,
    int actualSampleRate,
  ) async {
    if (!await Permission.microphone.request().isGranted) {
      if (kDebugMode) print('mic denied'); // do something here
      return;
    }
    await _audioCapture.start(
      (obj) => _listener(obj, refreshUi),
      _onError,
      sampleRate: actualSampleRate,
      bufferSize: 2048,
    );
    isRecording = true;
  }

  void _listener(dynamic obj, void Function(void Function()) refreshUi) {
    //raw samples → Dart list
    final buffer = Float32List.fromList(List<double>.from(obj));
    // final List<double> raw = buffer.toList();
    // wrap into NumDart real array
    final nd.Array realSignal = nd.Array(buffer);
    //convert to complex (fft needs ArrayComplex)
    final nd.ArrayComplex complexSignal = nd.arrayToComplexArray(realSignal);
    //run FFT
    final nd.ArrayComplex fftResult = sd.fft(complexSignal);
    //magnitudes & find peak
    final nd.Array magsArray = nd.arrayComplexAbs(fftResult);
    final List<double> mags = magsArray.toList();
    int maxI = 0;
    double maxM = mags[0];
    for (var i = 1; i < mags.length ~/ 2; i++) {
      if (mags[i] > maxM) {
        maxM = mags[i];
        maxI = i;
      }
    }

    final freqBin = _actualSampleRate! / obj.length;

    //final samples = obj.length;
    //final durationInSeconds = 0.161; // actual time of chunk (calculated before)

    //final estimatedSampleRate = samples / durationInSeconds;

    peakFrequency = maxI * freqBin;
    peakMagnitude = maxM * 1.0;

    if (peakFrequency! > 120 && peakFrequency! < 380 && peakMagnitude! > 500) {
      if (!_verdict) {
        refreshUi(() {
          omCount++;
        });
        _verdict = true;
      }
    } else {
      _verdict = false;
    }
    if (kDebugMode) {
      print(
        'maxI*freqBin: ${peakFrequency!.toStringAsFixed(1)} Hz | maxM ${peakMagnitude!.toStringAsFixed(1)}',
      );
    }
  }

  void _onError(Object e) {
    if (kDebugMode) print('Error: $e');
  }
}
