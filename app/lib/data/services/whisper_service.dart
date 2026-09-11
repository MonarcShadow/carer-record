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

  /// Detiene la grabación activa y transcribe el WAV resultante.
  Future<String?> stopAndTranscribe(String modelFolderAbsolutePath) async {
    final path = await _recorder.stop();
    if (path == null) return null;
    try {
      final result = await _transcribeWav(path, modelFolderAbsolutePath);
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return result;
    } catch (e) {
      return 'Error durante la transcripción: $e';
    }
  }

  /// Transcribe un WAV ya guardado en disco sin tocar el grabador.
  Future<String?> transcribeFromPath(
      String wavPath, String modelFolderAbsolutePath) async {
    final f = File(wavPath);
    if (!f.existsSync()) return 'Error: archivo de audio no encontrado';
    try {
      return await _transcribeWav(wavPath, modelFolderAbsolutePath);
    } catch (e) {
      return 'Error durante la transcripción: $e';
    }
  }

  /// Núcleo de transcripción (sin parar el recorder ni borrar archivos).
  Future<String> _transcribeWav(
      String wavPath, String modelFolderAbsolutePath) async {
    // Extraemos solo el nombre de la carpeta (whisper-base o whisper-small)
    final folderName = modelFolderAbsolutePath.split('/').last;
    final modelName = folderName.split('-').last; // 'base' o 'small'

    final modelsRoot = await _modelsPath();
    final encoderPath = '$modelsRoot/$folderName/$modelName-encoder.onnx';
    final decoderPath = '$modelsRoot/$folderName/$modelName-decoder.onnx';
    final tokensPath = '$modelsRoot/$folderName/$modelName-tokens.txt';

    if (!File(encoderPath).existsSync()) {
      return 'Error: Archivo de modelo no encontrado';
    }

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
        tokens: tokensPath,
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      ),
      decodingMethod: 'greedy_search',
    );

    final recognizer = sherpa.OfflineRecognizer(config);
    final stream = recognizer.createStream();

    // Leer el WAV y extraer muestras
    final bytes = File(wavPath).readAsBytesSync();
    final samples = _wavBytesToFloat32(bytes);

    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);

    final result = recognizer.getResult(stream);

    // Liberar memoria
    stream.free();
    recognizer.free();

    return result.text.trim();
  }

  Future<File?> stopAndGetFile() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
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

    final dataBytes = bytes.sublist(headerSize);
    final samples = Float32List(dataBytes.length ~/ 2);

    for (int i = 0; i < samples.length; i++) {
      final lo = dataBytes[i * 2];
      final hi = dataBytes[i * 2 + 1];
      int s16 = (hi << 8) | lo;
      if (s16 >= 32768) s16 -= 65536;
      samples[i] = s16 / 32768.0;
    }
    return samples;
  }
}
