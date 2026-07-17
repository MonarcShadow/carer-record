import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class WhisperService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;

  Future<String> _modelsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models';
  }

  Future<void> startRecording() async {
    final dir = await getApplicationDocumentsDirectory();
    _currentRecordingPath = '${dir.path}/temp_whisper.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: _currentRecordingPath!,
    );
  }

  Future<String?> stopAndTranscribe(String modelFolderAbsolutePath) async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final modelsPath = await _modelsPath();
    
    // Extraemos solo el nombre de la carpeta (whisper-base o whisper-small)
    final folderName = modelFolderAbsolutePath.split('/').last; 
    final modelName  = folderName.split('-').last; // 'base' o 'small'

    // Reconstruimos la ruta correcta
    final encoderPath = '$modelsPath/$folderName/$modelName-encoder.onnx';
    final decoderPath = '$modelsPath/$folderName/$modelName-decoder.onnx';
    final tokensPath  = '$modelsPath/$folderName/$modelName-tokens.txt';

    if (!File(encoderPath).existsSync()) {
      return 'Error: Archivo de modelo no encontrado';
    }

    try {
      // 1. SOLUCIÓN CRÍTICA: Inicializar los bindings nativos de Sherpa ONNX
      sherpa.initBindings();

      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            language: 'es', // Mejora la detección obligando al español
            task: 'transcribe',
          ),
          tokens:    tokensPath,
          modelType: 'whisper',
          numThreads: 2,
          debug: false,
        ),
        decodingMethod: 'greedy_search',
      );

      final recognizer = sherpa.OfflineRecognizer(config);
      final stream     = recognizer.createStream();

      // Leer el WAV y extraer muestras
      final bytes   = File(path).readAsBytesSync();
      final samples = _wavBytesToFloat32(bytes);

      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);

      final result = recognizer.getResult(stream);
      
      // Liberar memoria
      stream.free();
      recognizer.free();

      // Limpiar archivo temporal
      File(path).deleteSync();

      return result.text.trim();
    } catch (e) {
      return 'Error durante la transcripción: $e';
    }
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> cancelRecording() async {
    await _recorder.stop();
    if (_currentRecordingPath != null) {
      final f = File(_currentRecordingPath!);
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Convierte bytes WAV a Float32List de muestras normalizadas
  Float32List _wavBytesToFloat32(Uint8List bytes) {
    // Saltar header WAV (44 bytes estándar)
    const headerSize = 44;
    
    // Evitar colapso si la grabación fue menor a un milisegundo o falló
    if (bytes.length <= headerSize) return Float32List(0);
    
    final dataBytes  = bytes.sublist(headerSize);
    final samples    = Float32List(dataBytes.length ~/ 2);

    for (int i = 0; i < samples.length; i++) {
      final lo    = dataBytes[i * 2];
      final hi    = dataBytes[i * 2 + 1];
      int   s16   = (hi << 8) | lo;
      if (s16 >= 32768) s16 -= 65536;
      samples[i]  = s16 / 32768.0;
    }
    return samples;
  }
}