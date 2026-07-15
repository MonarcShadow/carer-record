import 'package:flutter/material.dart';
import '../../core/theme.dart';

enum WhisperModel { base, small }
enum LlmModel { gemma3, none }

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  WhisperModel _whisperModel = WhisperModel.base;
  LlmModel     _llmModel     = LlmModel.none;

  bool _whisperBaseDownloaded  = false;
  bool _whisperSmallDownloaded = false;
  bool _gemmaDownloaded        = false;

  bool _downloadingWhisperBase  = false;
  bool _downloadingWhisperSmall = false;
  bool _downloadingGemma        = false;

  double _whisperBaseProgress  = 0;
  double _whisperSmallProgress = 0;
  double _gemmaProgress        = 0;

  final _testController = TextEditingController();
  String _testResult    = '';

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  Future<void> _downloadWhisperBase() async {
    setState(() { _downloadingWhisperBase = true; _whisperBaseProgress = 0; });
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() => _whisperBaseProgress = i / 10);
    }
    setState(() { _downloadingWhisperBase = false; _whisperBaseDownloaded = true; });
  }

  Future<void> _downloadWhisperSmall() async {
    setState(() { _downloadingWhisperSmall = true; _whisperSmallProgress = 0; });
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() => _whisperSmallProgress = i / 10);
    }
    setState(() { _downloadingWhisperSmall = false; _whisperSmallDownloaded = true; });
  }

  Future<void> _downloadGemma() async {
    setState(() { _downloadingGemma = true; _gemmaProgress = 0; });
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => _gemmaProgress = i / 10);
    }
    setState(() { _downloadingGemma = false; _gemmaDownloaded = true; });
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
            _SectionHeader(
              icon: Icons.mic,
              title: 'Voz a texto',
              subtitle: 'Whisper — transcripción on-device sin conexión',
            ),
            const SizedBox(height: 12),

            _ModelCard(
              title: 'Whisper Base',
              description: '~74 MB · Mayor velocidad, menor precisión',
              selected: _whisperModel == WhisperModel.base,
              downloaded: _whisperBaseDownloaded,
              downloading: _downloadingWhisperBase,
              progress: _whisperBaseProgress,
              onSelect: () => setState(() => _whisperModel = WhisperModel.base),
              onDownload: _downloadingWhisperBase ? null : _downloadWhisperBase,
              onDelete: _whisperBaseDownloaded
                  ? () => setState(() {
                        _whisperBaseDownloaded = false;
                        _whisperBaseProgress   = 0;
                      })
                  : null,
            ),
            const SizedBox(height: 10),
            _ModelCard(
              title: 'Whisper Small',
              description: '~244 MB · Mayor precisión, menor velocidad',
              selected: _whisperModel == WhisperModel.small,
              downloaded: _whisperSmallDownloaded,
              downloading: _downloadingWhisperSmall,
              progress: _whisperSmallProgress,
              onSelect: () => setState(() => _whisperModel = WhisperModel.small),
              onDownload: _downloadingWhisperSmall ? null : _downloadWhisperSmall,
              onDelete: _whisperSmallDownloaded
                  ? () => setState(() {
                        _whisperSmallDownloaded = false;
                        _whisperSmallProgress   = 0;
                      })
                  : null,
            ),

            const SizedBox(height: 32),

            // ── Limpieza y resumen ────────────────────────────────────
            _SectionHeader(
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
              onSelect: () => setState(() => _llmModel = LlmModel.none),
              onDownload: null,
              hideDownload: true,
            ),
            const SizedBox(height: 10),
            _ModelCard(
              title: 'Gemma 3 1B INT4',
              description: '~529 MB · Limpieza clínica on-device',
              selected: _llmModel == LlmModel.gemma3,
              downloaded: _gemmaDownloaded,
              downloading: _downloadingGemma,
              progress: _gemmaProgress,
              onSelect: () => setState(() => _llmModel = LlmModel.gemma3),
              onDownload: _downloadingGemma ? null : _downloadGemma,
              onDelete: _gemmaDownloaded
                  ? () => setState(() {
                        _gemmaDownloaded = false;
                        _gemmaProgress   = 0;
                      })
                  : null,
            ),

            const SizedBox(height: 32),

            // ── Área de prueba ────────────────────────────────────────
            _SectionHeader(
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
  final bool selected;
  final bool downloaded;
  final bool downloading;
  final double progress;
  final VoidCallback onSelect;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final bool hideDownload;

  const _ModelCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.downloaded,
    required this.downloading,
    required this.progress,
    required this.onSelect,
    required this.onDownload,
    this.onDelete,
    this.hideDownload = false,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? AppTheme.primary
                      : const Color(0xFF9CA3AF),
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
                    ),
                ],
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFE5E7EB),
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}