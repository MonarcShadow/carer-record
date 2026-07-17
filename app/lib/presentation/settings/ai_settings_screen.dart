import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/theme.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/whisper_service.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';


enum WhisperModel {none, base, small }
enum LlmModel { none, t5Small, gemma3 }

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> with SingleTickerProviderStateMixin {
  // URLs de los modelos
  static const _whisperBaseUrl  = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2';
  static const _whisperSmallUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2';
  static const _t5SmallUrl      = 'placeholder'; // Reemplaza con la URL de tu t5-small.tar.bz2
  static const _gemmaUrl        = 'placeholder'; // Reemplaza con la URL de tu gemma-3.tar.bz2

  WhisperModel _whisperModel = WhisperModel.base;
  LlmModel     _llmModel     = LlmModel.none;

  // Estados de descarga
  bool _whisperBaseDownloaded  = false;
  bool _whisperSmallDownloaded = false;
  bool _t5SmallDownloaded      = false;
  bool _gemmaDownloaded        = false;

  // Estados de proceso
  bool _downloadingWhisperBase  = false;
  bool _downloadingWhisperSmall = false;
  bool _downloadingT5Small      = false;
  bool _downloadingGemma        = false;

  // Progresos
  double _whisperBaseProgress  = 0;
  double _whisperSmallProgress = 0;
  double _t5SmallProgress      = 0;
  double _gemmaProgress        = 0;

  // Textos de estado (Descargando vs Instalando)
  String _whisperBaseStatus  = '';
  String _whisperSmallStatus = '';
  String _t5SmallStatus      = '';
  String _gemmaStatus        = '';

  final _testController = TextEditingController();
  String _testResult    = '';

  final WhisperService _whisperService = WhisperService();
  bool _isRecording    = false;
  bool _transcribing   = false;

  // Animaciones para la barra de audio
  late AnimationController _micAnimationController;
  Timer? _waveformTimer;
  Timer? _transcriptionTimer; // Timer para la transcripción en tiempo real
  final List<double> _amplitudes = List.filled(20, 0.1);

  String _whisperFolder() =>
      _whisperModel == WhisperModel.base ? 'whisper-base' : 'whisper-small';

  bool get _micAvailable =>
      _whisperModel != WhisperModel.none &&
      (_whisperModel == WhisperModel.base
          ? _whisperBaseDownloaded
          : _whisperSmallDownloaded);

  bool get _processAvailable => _llmModel != LlmModel.none;

  @override
  void initState() {
    super.initState();
    _loadDownloadState();
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _testController.dispose();
    _micAnimationController.dispose();
    _waveformTimer?.cancel();
    _transcriptionTimer?.cancel();
    super.dispose();
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopAndTranscribe();
    } else {
      _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de micrófono denegado')),
        );
      }
      return;
    }
    
    // Quitar el foco del TextField para esconder el teclado al grabar
    // Mover antes de operaciones async para evitar usar BuildContext
    // a través de brechas async (lint: use_build_context_synchronously).
    FocusManager.instance.primaryFocus?.unfocus();
    
    // NOTA: Para transcripción en streaming (tiempo real)
    // sherpa-onnx requiere el OnlineRecognizer, no el OfflineRecognizer.
    // Whisper en sherpa-onnx es un modelo OFFLINE (procesa lotes de audio).
    // Para simular el "tiempo real" con un modelo offline, 
    // lo habitual es detener y reiniciar la grabación en trozos,
    // o cambiar a un modelo Online (ej: zipformer) si quieres verdadero streaming.
    // 
    // Como tu servicio actual (WhisperService) usa OfflineRecognizer con Whisper,
    // transcribir "mientras hablas" requiere modificar el servicio
    // para capturar el stream de audio continuamente, o aceptar 
    // que la transcripción llegará al finalizar.
    // 
    // Por ahora, WhisperService requiere detener la grabación para transcribir el archivo WAV completo.
    
    await _whisperService.startRecording();
    
    setState(() {
      _isRecording  = true;
      _testResult   = '';
      _testController.text = 'Escuchando...'; // Feedback visual de que está activo
    });
    
    _micAnimationController.forward();
    _startWaveformSimulation();
  }

  Future<void> _stopAndTranscribe() async {
    _waveformTimer?.cancel();
    _micAnimationController.reverse();
    
    setState(() { 
      _isRecording = false; 
      _transcribing = true; 
      // Reiniciar amplitudes
      for (int i = 0; i < _amplitudes.length; i++) {
        _amplitudes[i] = 0.1;
      }
    });
    
    _testController.text = 'Procesando audio...';

    // 1. Obtener la ruta absoluta completa donde están los modelos
    final modelsPath = await _modelsDir();
    final absoluteModelPath = '$modelsPath/${_whisperFolder()}';

    // 2. Pasar la ruta absoluta a tu WhisperService
    final result = await _whisperService.stopAndTranscribe(absoluteModelPath);

    setState(() {
      _transcribing = false;
      _testController.text = result ?? '';
      _testResult = '';
    });
  }

  // Simula la actividad del micrófono para la animación
  void _startWaveformSimulation() {
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _amplitudes.length; i++) {
          // Genera valores aleatorios para simular amplitud.
          // En una implementación real, esto vendría del nivel de decibelios del micrófono.
          _amplitudes[i] = math.max(0.1, math.Random().nextDouble());
        }
      });
    });
  }


  Future<String> _modelsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);
    return modelsDir.path;
  }

  bool _whisperBaseExists(String modelsPath) {
    return File('$modelsPath/whisper-base/base-encoder.onnx').existsSync() &&
           File('$modelsPath/whisper-base/base-decoder.onnx').existsSync() &&
           File('$modelsPath/whisper-base/base-tokens.txt').existsSync();
  }

  bool _whisperSmallExists(String modelsPath) {
    return File('$modelsPath/whisper-small/small-encoder.onnx').existsSync() &&
           File('$modelsPath/whisper-small/small-decoder.onnx').existsSync() &&
           File('$modelsPath/whisper-small/small-tokens.txt').existsSync();
  }

  // Verificación genérica para LLMs (verifica si la carpeta existe y no está vacía)
  bool _folderExistsAndNotEmpty(String modelsPath, String folder) {
    final dir = Directory('$modelsPath/$folder');
    return dir.existsSync() && dir.listSync().isNotEmpty;
  }

  Future<void> _downloadAndExtract({
    required String url,
    required String folderName,
    required void Function(double progress, String status) onUpdate,
    required void Function() onDone,
    required void Function(String) onError,
  }) async {
    final modelsPath = await _modelsDir();
    // 1. Usamos puros Strings para no enviar objetos que hagan fallar al Isolate
    final tempFilePath = '$modelsPath/$folderName.tar.bz2';
    final outDirPath = '$modelsPath/$folderName';
    final dio = Dio();

    try {
      // Fase de Descarga (Esta parte funcionaba bien, no la alteramos)
      await dio.download(
        url,
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onUpdate(received / total, 'Descargando');
          }
        },
      );

      // Fase de Instalación (Donde ocurría el colapso)
      onUpdate(1.0, 'Instalando...');

      await compute(_extractTarInBackground, {
        'tempFilePath': tempFilePath,
        'outDirPath':   outDirPath,
        });

      onDone();

    } catch (e) {
      final tempFile = File(tempFilePath);
      if (tempFile.existsSync()) tempFile.deleteSync();
      
      // 3. Recortamos el error masivo para que no cubra la interfaz
      String errorMsg = e.toString();
      if (errorMsg.length > 150) {
        errorMsg = '${errorMsg.substring(0, 147)}...';
      }
      onError(errorMsg);
    }
  }

  Future<void> _downloadWhisperBase() async {
    setState(() { _downloadingWhisperBase = true; _whisperBaseProgress = 0; _whisperBaseStatus = 'Iniciando...'; });
    await _downloadAndExtract(
      url:        _whisperBaseUrl,
      folderName: 'whisper-base',
      onUpdate: (p, s) => setState(() { _whisperBaseProgress = p; _whisperBaseStatus = s; }),
      onDone: () async {
        setState(() { _downloadingWhisperBase = false; _whisperBaseDownloaded = true; });
        await _saveDownloadState();
      },
      onError: (e) => _showError(e, () => setState(() => _downloadingWhisperBase = false)),
    );
  }

  Future<void> _downloadWhisperSmall() async {
    setState(() { _downloadingWhisperSmall = true; _whisperSmallProgress = 0; _whisperSmallStatus = 'Iniciando...'; });
    await _downloadAndExtract(
      url:        _whisperSmallUrl,
      folderName: 'whisper-small',
      onUpdate: (p, s) => setState(() { _whisperSmallProgress = p; _whisperSmallStatus = s; }),
      onDone: () async {
        setState(() { _downloadingWhisperSmall = false; _whisperSmallDownloaded = true; });
        await _saveDownloadState();
      },
      onError: (e) => _showError(e, () => setState(() => _downloadingWhisperSmall = false)),
    );
  }

  Future<void> _downloadT5Small() async {
    setState(() { _downloadingT5Small = true; _t5SmallProgress = 0; _t5SmallStatus = 'Iniciando...'; });
    await _downloadAndExtract(
      url:        _t5SmallUrl,
      folderName: 't5-small',
      onUpdate: (p, s) => setState(() { _t5SmallProgress = p; _t5SmallStatus = s; }),
      onDone: () async {
        setState(() { _downloadingT5Small = false; _t5SmallDownloaded = true; });
        await _saveDownloadState();
      },
      onError: (e) => _showError(e, () => setState(() => _downloadingT5Small = false)),
    );
  }

  Future<void> _downloadGemma() async {
    setState(() { _downloadingGemma = true; _gemmaProgress = 0; _gemmaStatus = 'Iniciando...'; });
    await _downloadAndExtract(
      url:        _gemmaUrl,
      folderName: 'gemma-3',
      onUpdate: (p, s) => setState(() { _gemmaProgress = p; _gemmaStatus = s; }),
      onDone: () async {
        setState(() { _downloadingGemma = false; _gemmaDownloaded = true; });
        await _saveDownloadState();
      },
      onError: (e) => _showError(e, () => setState(() => _downloadingGemma = false)),
    );
  }

  void _showError(String error, VoidCallback onReset) {
    onReset();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadDownloadState() async {
    final prefs      = await SharedPreferences.getInstance();
    final modelsPath = await _modelsDir();

    if (!mounted) return;

    setState(() {
      _whisperBaseDownloaded  = (prefs.getBool('whisper_base_downloaded')  ?? false) && _whisperBaseExists(modelsPath);
      _whisperSmallDownloaded = (prefs.getBool('whisper_small_downloaded') ?? false) && _whisperSmallExists(modelsPath);
      _t5SmallDownloaded      = (prefs.getBool('t5_small_downloaded')      ?? false) && _folderExistsAndNotEmpty(modelsPath, 't5-small');
      _gemmaDownloaded        = (prefs.getBool('gemma_downloaded')         ?? false) && _folderExistsAndNotEmpty(modelsPath, 'gemma-3');
      
      _whisperModel = WhisperModel.values[prefs.getInt('whisper_model') ?? 0];
      
      int llmIndex = prefs.getInt('llm_model') ?? 0;
      _llmModel = (llmIndex >= 0 && llmIndex < LlmModel.values.length) 
          ? LlmModel.values[llmIndex] 
          : LlmModel.none;
    });
  }

  Future<void> _saveDownloadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('whisper_base_downloaded',  _whisperBaseDownloaded);
    await prefs.setBool('whisper_small_downloaded', _whisperSmallDownloaded);
    await prefs.setBool('t5_small_downloaded',      _t5SmallDownloaded);
    await prefs.setBool('gemma_downloaded',         _gemmaDownloaded);
    await prefs.setInt('whisper_model', _whisperModel.index);
    await prefs.setInt('llm_model', _llmModel.index);
  }

  Future<void> _deleteModel(String folderName, VoidCallback onUpdateState) async {
    final modelsPath = await _modelsDir();
    final dir = Directory('$modelsPath/$folderName');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    onUpdateState();
    await _saveDownloadState();
  }

  Future<void> _runTest() async {
    if (_testController.text.isEmpty) return;
    setState(() => _testResult = 'Procesando...');
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _testResult =
        '[Simulación] Texto procesado: "${_testController.text}"');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Configuración de IA'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        // Para cerrar el teclado si se toca fuera de los inputs
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Voz a texto ───────────────────────────────────────────
              const _SectionHeader(
                icon: Icons.mic,
                title: 'Voz a texto',
                subtitle: 'Whisper — transcripción on-device sin conexión',
              ),
              const SizedBox(height: 12),

              _ModelCard(
                title: 'Sin Notas de voz',
                description: 'No se transcribirá audio, solo texto escrito',
                url: _whisperBaseUrl,
                selected: _whisperModel == WhisperModel.none,
                downloaded: true,
                downloading: false,
                progress: 0,
                statusText: '',
                onSelect: () async {
                  setState(() => _whisperModel = WhisperModel.none);
                  await _saveDownloadState();
                },
                onDownload: null,
                hideDownload: true,
              ),


              const SizedBox(height: 12),

              _ModelCard(
                title: 'Whisper Base',
                description: '~198 MB · Mayor velocidad, menor precisión',
                url: _whisperBaseUrl,
                selected: _whisperModel == WhisperModel.base,
                downloaded: _whisperBaseDownloaded,
                downloading: _downloadingWhisperBase,
                progress: _whisperBaseProgress,
                statusText: _whisperBaseStatus,
                onSelect: () async {
                  setState(() => _whisperModel = WhisperModel.base);
                  await _saveDownloadState();
                },
                onDownload: _downloadingWhisperBase ? null : _downloadWhisperBase,
                onDelete: _whisperBaseDownloaded
                    ? () => _deleteModel('whisper-base', () => setState(() => _whisperBaseDownloaded = false))
                    : null,
              ),
              const SizedBox(height: 10),
              
              _ModelCard(
                title: 'Whisper Small',
                description: '~610 MB · Mayor precisión, menor velocidad',
                url: _whisperSmallUrl,
                selected: _whisperModel == WhisperModel.small,
                downloaded: _whisperSmallDownloaded,
                downloading: _downloadingWhisperSmall,
                progress: _whisperSmallProgress,
                statusText: _whisperSmallStatus,
                onSelect: () async {
                  setState(() => _whisperModel = WhisperModel.small);
                  await _saveDownloadState();
                },
                onDownload: _downloadingWhisperSmall ? null : _downloadWhisperSmall,
                onDelete: _whisperSmallDownloaded
                    ? () => _deleteModel('whisper-small', () => setState(() => _whisperSmallDownloaded = false))
                    : null,
              ),

              const SizedBox(height: 32),

              // ── Limpieza y resumen ────────────────────────────────────
              const _SectionHeader(
                icon: Icons.auto_fix_high,
                title: 'Limpieza y resumen',
                subtitle: 'Mejora el texto transcrito para notas clínicas',
              ),
              const SizedBox(height: 12),

              _ModelCard(
                title: 'Sin limpieza',
                description: 'Usa el texto de Whisper directamente',
                selected: _llmModel == LlmModel.none,
                downloaded: true,
                downloading: false,
                progress: 0,
                statusText: '',
                onSelect: () async {
                  setState(() => _llmModel = LlmModel.none);
                  await _saveDownloadState();
                },
                onDownload: null,
                hideDownload: true,
              ),
              const SizedBox(height: 10),

              _ModelCard(
                title: 'T5 Small',
                description: 'Medida ligera · Corrección rápida, limpieza y resumen básico',
                url: _t5SmallUrl,
                selected: _llmModel == LlmModel.t5Small,
                downloaded: _t5SmallDownloaded,
                downloading: _downloadingT5Small,
                progress: _t5SmallProgress,
                statusText: _t5SmallStatus,
                onSelect: () async {
                  setState(() => _llmModel = LlmModel.t5Small);
                  await _saveDownloadState();
                },
                onDownload: _downloadingT5Small ? null : _downloadT5Small,
                onDelete: _t5SmallDownloaded
                    ? () => _deleteModel('t5-small', () => setState(() => _t5SmallDownloaded = false))
                    : null,
              ),
              const SizedBox(height: 10),

              _ModelCard(
                title: 'Gemma 3 1B INT4',
                description: '~529 MB · Limpieza clínica mas precisa.\\nEs mas lento',
                url: _gemmaUrl,
                selected: _llmModel == LlmModel.gemma3,
                downloaded: _gemmaDownloaded,
                downloading: _downloadingGemma,
                progress: _gemmaProgress,
                statusText: _gemmaStatus,
                onSelect: () async {
                  setState(() => _llmModel = LlmModel.gemma3);
                  await _saveDownloadState();
                },
                onDownload: _downloadingGemma ? null : _downloadGemma,
                onDelete: _gemmaDownloaded
                    ? () => _deleteModel('gemma-3', () => setState(() => _gemmaDownloaded = false))
                    : null,
              ),

              const SizedBox(height: 32),

              // ── Área de prueba ────────────────────────────────────────
              const _SectionHeader(
                icon: Icons.science,
                title: 'Área de prueba',
                subtitle: 'Graba o escribe para probar la configuración actual',
              ),
              const SizedBox(height: 12),

              // Animación de botón de micrófono expandible
              Center(
                child: AnimatedBuilder(
                  animation: _micAnimationController,
                  builder: (context, child) {
                    // Valores de animación
                    final expansionValue = _micAnimationController.value;
                    // Anchura dinámica: desde 64 (botón circular) hasta ~300 (barra expandida)
                    final width = 64.0 + (expansionValue * 220.0);
                    
                    return GestureDetector(
                      onTap: _micAvailable && !_transcribing ? _toggleRecording : null,
                      child: Container(
                        width: width,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          color: !_micAvailable
                              ? const Color(0xFFE5E7EB)
                              : _isRecording
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : AppTheme.primary,
                          // Se elimina el borde rojo del contenedor principal para que no se vea el doble borde
                          // border: _isRecording ? Border.all(color: Colors.red, width: 2) : null,
                          boxShadow: _isRecording
                              ? [BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                )]
                              : [BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )],
                        ),
                        child: Stack(
                          children: [
                            // Contenido expandido (Onda de audio y borde exterior simulado)
                            if (expansionValue > 0)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: expansionValue,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(32),
                                      border: Border.all(color: Colors.red, width: 2), // Borde animado
                                    ),
                                    child: Padding(
                                      // Padding ajustado: left 64 para saltar el circulo rojo, right 20 para espaciado
                                      padding: const EdgeInsets.only(left: 64.0, right: 20.0), 
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: List.generate(_amplitudes.length, (index) {
                                              return Flexible(
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 100),
                                                    width: 3, 
                                                    height: 32 * _amplitudes[index],
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          );
                                        }
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            
                            // Icono de micrófono deslizable (El círculo sólido)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 64,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: !_micAvailable
                                      ? Colors.transparent
                                      : _isRecording
                                          ? Colors.red // Círculo sólido rojo
                                          : Colors.transparent,
                                ),
                                child: Center(
                                  child: Icon(
                                    _isRecording ? Icons.stop : Icons.mic,
                                    color: !_micAvailable 
                                        ? Colors.grey 
                                        : _isRecording ? Colors.white : Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  !_micAvailable
                      ? 'Descarga un modelo de voz para activar'
                      : _isRecording
                          ? 'Toca para detener'
                          : _transcribing
                              ? 'Transcribiendo...'
                              : 'Toca para grabar',
                  style: TextStyle(
                    fontSize: 12,
                    color: !_micAvailable
                        ? AppTheme.textSecondary
                        : _isRecording
                            ? Colors.red
                            : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _testController,
                maxLines: 4,
                readOnly: _transcribing,
                decoration: InputDecoration(
                  hintText: 'El texto transcrito aparecerá aquí...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _processAvailable && _testController.text.isNotEmpty && !_transcribing
                      ? _runTest
                      : null,
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text(_processAvailable
                      ? 'Limpiar con IA'
                      : 'Selecciona un modelo de limpieza'),
                ),
              ),

              if (_testResult.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resultado:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(_testResult,
                          style: const TextStyle(
                              fontSize: 14, color: AppTheme.textPrimary)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// Función top-level para ejecutar en compute()
void _extractTarInBackground(Map<String, String> args) {
  final tempFilePath = args['tempFilePath']!;
  final outDirPath   = args['outDirPath']!;

  final bytes = File(tempFilePath).readAsBytesSync();
  final bz2   = BZip2Decoder().decodeBytes(bytes);
  final tar   = TarDecoder().decodeBytes(bz2);
  final outDir = Directory(outDirPath);

  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  for (final file in tar.files) {
    if (file.isFile) {
      final name    = file.name.split('/').last;
      final outFile = File('${outDir.path}/$name');
      outFile.writeAsBytesSync(file.content as List<int>);
    }
  }
  File(tempFilePath).deleteSync();
}

// ── Widgets auxiliares ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  final String title;
  final String description;
  final String? url;
  final bool selected;
  final bool downloaded;
  final bool downloading;
  final double progress;
  final String statusText;
  final VoidCallback onSelect;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final bool hideDownload;

  const _ModelCard({
    required this.title,
    required this.description,
    this.url,
    required this.selected,
    required this.downloaded,
    required this.downloading,
    required this.progress,
    required this.statusText,
    required this.onSelect,
    required this.onDownload,
    this.onDelete,
    this.hideDownload = false,
  });

  @override
  Widget build(BuildContext context) {
    final isInstalling = statusText == 'Instalando...';

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? AppTheme.primary
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(description,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                if (!hideDownload) ...[
                  if (downloading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary),
                    )
                  else if (downloaded) ...[
                    const Icon(Icons.check_circle,
                        color: AppTheme.primary, size: 22),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 20),
                        onPressed: onDelete,
                        tooltip: 'Eliminar modelo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ] else
                    IconButton(
                      icon: const Icon(Icons.download,
                          color: AppTheme.primary),
                      onPressed: onDownload,
                      tooltip: 'Descargar modelo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: isInstalling ? null : progress,
                backgroundColor: const Color(0xFFE5E7EB),
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    statusText,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primary),
                  ),
                  if (!isInstalling)
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}