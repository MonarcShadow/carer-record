import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/theme.dart';

import 'dart:io';


enum WhisperModel {none, base, small }
enum LlmModel { none, t5Small, gemma3 }

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadDownloadState();
  }

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
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
      body: SingleChildScrollView(
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
              description: '~529 MB · Limpieza clínica mas precisa.\nEs mas lento',
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
              subtitle: 'Escribe o dicta texto para probar la configuración actual',
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _testController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Escribe aquí para probar el modelo seleccionado...',
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
                onPressed: _runTest,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Procesar texto'),
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