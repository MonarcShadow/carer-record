import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/notes_service.dart';
import '../../data/services/whisper_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../settings/ai_settings_screen.dart'; // para los enums WhisperModel / LlmModel

class NotesScreen extends StatefulWidget {
  final String          patientId;
  final String          patientName;
  final LoginResponseDto currentUser;

  const NotesScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.currentUser,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with SingleTickerProviderStateMixin {
  final NotesService    _service       = NotesService();
  final WhisperService  _whisperService = WhisperService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController      _scrollCtrl = ScrollController();

  // ── Estado AI leído de SharedPreferences ──────────────────────────────────
  WhisperModel _whisperModel      = WhisperModel.none;
  LlmModel     _llmModel          = LlmModel.none;
  bool         _whisperDownloaded = false;
  String       _modelsPath        = '';

  bool get _micAvailable =>
      _whisperModel != WhisperModel.none && _whisperDownloaded;

  bool get _aiAvailable => _llmModel != LlmModel.none;

  List<NoteModel> _notes   = [];
  bool    _loading          = true;
  bool    _sending          = false;
  String? _error;

  // Micrófono
  bool   _isRecording  = false;
  bool   _transcribing = false;
  bool   _uploadingAudio = false;
  late AnimationController _micAnim;
  Timer? _waveformTimer;
  Timer? _pollTimer;
  final List<double> _amplitudes = List.filled(20, 0.1);
  DateTime? _recordingStarted;

  // IA (simulación por ahora, igual que en AiSettingsScreen)
  bool   _processingAi = false;

  @override
  void initState() {
    super.initState();
    _micAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadAiState();
    _loadNotes();
    _startPollingIfNeeded();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _micAnim.dispose();
    _waveformTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Carga ──────────────────────────────────────────────────────────────────
  Future<void> _loadAiState() async {
    final prefs = await SharedPreferences.getInstance();
    final documentsDir = await getApplicationDocumentsDirectory();
    final path = '${documentsDir.path}/models';
    final modelsDir = Directory(path);
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final whisperIndex = prefs.getInt('whisper_model') ?? 0;
    final wModel = WhisperModel.values[whisperIndex];

    bool downloaded = false;
    if (wModel == WhisperModel.base) {
      downloaded = File('$path/whisper-base/base-encoder.onnx').existsSync() &&
                   File('$path/whisper-base/base-decoder.onnx').existsSync() &&
                   File('$path/whisper-base/base-tokens.txt').existsSync();
    } else if (wModel == WhisperModel.small) {
      downloaded = File('$path/whisper-small/small-encoder.onnx').existsSync() &&
                   File('$path/whisper-small/small-decoder.onnx').existsSync() &&
                   File('$path/whisper-small/small-tokens.txt').existsSync();
    }

    final llmIndex = prefs.getInt('llm_model') ?? 0;
    final lModel = (llmIndex >= 0 && llmIndex < LlmModel.values.length)
        ? LlmModel.values[llmIndex]
        : LlmModel.none;

    if (!mounted) return;

    setState(() {
      _whisperModel = wModel;
      _whisperDownloaded = downloaded;
      _llmModel = lModel;
      _modelsPath = path;
    });
  }

  Future<void> _loadNotes() async {
    final showInitialLoading = _notes.isEmpty;
    setState(() {
      if (showInitialLoading) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final notes = await _service.getNotes(widget.patientId);
      setState(() { _notes = notes; _loading = false; });
      _scrollToBottom();
      _startPollingIfNeeded();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (_notes.any((n) => n.isPending)) {
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        await _loadNotes();
        if (!_notes.any((n) => n.isPending)) {
          _pollTimer?.cancel();
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Enviar nota ────────────────────────────────────────────────────────────
  Future<void> _sendNote() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final note = await _service.createNote(
        patientId: widget.patientId,
        authorId:  widget.currentUser.userId,
        content:   text,
        inputMethod: _wasVoice ? 'voice' : 'text',
        transcriptionSource: _wasVoice ? 'auto_whisper' : 'manual',
        audioConfirmed: true,  // siempre true cuando se envía texto, sea escrito o transcrito por Whisper local
                               // false se reserva para cuando el servidor transcriba audio sin revisión del usuario
      );
      _inputCtrl.clear();
      _wasVoice = false;
      setState(() { _notes.add(note); _sending = false; });
      _scrollToBottom();
    } catch (e) {
      setState(() => _sending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  bool _wasVoice = false;

  // ── Micrófono ──────────────────────────────────────────────────────────────
  Future<void> _toggleMic() async {
    if (_isRecording) {
      if (_micAvailable) {
        await _stopAndTranscribe();
      } else {
        await _stopAndUpload();
      }
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Permiso de micrófono denegado'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await _whisperService.startRecording();
    _recordingStarted = DateTime.now();
    setState(() {
      _isRecording = true;
      _inputCtrl.text = 'Escuchando...';
    });
    _micAnim.forward();
    _waveformTimer = Timer.periodic(
      const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < _amplitudes.length; i++) {
            _amplitudes[i] = math.max(0.1, math.Random().nextDouble());
          }
        });
      });
  }

    Future<void> _stopAndUpload() async {
      _waveformTimer?.cancel();
      _micAnim.reverse();
      final recordedAt = _recordingStarted ?? DateTime.now();
      setState(() {
        _isRecording = false;
        _uploadingAudio = true;
        for (int i = 0; i < _amplitudes.length; i++) {
          _amplitudes[i] = 0.1;
        }
      });
      _inputCtrl.text = 'Enviando audio al servidor...';

      try {
        final audioFile = await _whisperService.stopAndGetFile();
        if (audioFile == null) {
          throw Exception('No se pudo recuperar el audio grabado');
        }
        final note = await _service.uploadAudio(
          patientId:  widget.patientId,
          authorId:   widget.currentUser.userId,
          recordedAt: recordedAt.toIso8601String(),
          audioFile:  audioFile,
        );
        _inputCtrl.clear();
        setState(() {
          _notes.add(note);
          _uploadingAudio = false;
        });
        _scrollToBottom();
      } catch (e) {
        setState(() => _uploadingAudio = false);
        _inputCtrl.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()),
                backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }
    }

  Future<void> _stopAndTranscribe() async {
    _waveformTimer?.cancel();
    _micAnim.reverse();
    setState(() {
      _isRecording  = false;
      _transcribing = true;
      for (int i = 0; i < _amplitudes.length; i++) {
        _amplitudes[i] = 0.1;
      }
    });
    _inputCtrl.text = 'Procesando audio...';

    final folder = _whisperModel == WhisperModel.base
        ? 'whisper-base'
        : 'whisper-small';
    final result = await _whisperService.stopAndTranscribe('$_modelsPath/$folder');
    setState(() {
      _transcribing = false;
      _wasVoice = true;
      _inputCtrl.text = result ?? '';
    });
  }

  // ── IA ─────────────────────────────────────────────────────────────────────
  Future<void> _runAi() async {
    if (_inputCtrl.text.trim().isEmpty) return;
    setState(() => _processingAi = true);
    // Simulación — igual que AiSettingsScreen._runTest
    // Aquí se integrará Gemma / T5 cuando estén disponibles
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _processingAi = false;
      // Por ahora no modifica el texto; cuando el modelo esté listo
      // reemplazará _inputCtrl.text con el resultado limpio
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Limpieza con IA pendiente de integrar el modelo')),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _roleLabel(String r) => switch (r) {
    'admin'  => 'Administrador',
    'doctor' => 'Médico',
    'nurse'  => 'Enfermería',
    'tech'   => 'Equipo Ampliado',
    _        => r,
  };

  String _fmtTime(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final date = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final diff = today.difference(date).inDays;

      final time = '${dt.hour.toString().padLeft(2,'0')}:'
                   '${dt.minute.toString().padLeft(2,'0')}';
      if (diff == 0) return time;
      if (diff == 1) return 'Ayer  $time';
      return '${dt.day.toString().padLeft(2,'0')}/'
             '${dt.month.toString().padLeft(2,'0')}/'
             '${dt.year}  $time';
    } catch (_) { return raw; }
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  bool _isMe(NoteModel n) => n.authorId == widget.currentUser.userId;

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final busy   = _transcribing || _processingAi || _uploadingAudio;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notas clínicas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.patientName,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: _loadNotes),
        ],
      ),
      body: Column(
        children: [
          // ── Lista de notas ───────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(theme)
                    : _notes.isEmpty
                        ? _buildEmpty(theme)
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                            itemCount: _notes.length,
                            itemBuilder: (_, i) =>
                                _buildBubble(_notes[i], theme, isDark),
                          ),
          ),

          // ── Barra de entrada ─────────────────────────────────────────
          _buildInputBar(theme, isDark, busy),
        ],
      ),
    );
  }

  // ── Burbuja de nota ────────────────────────────────────────────────────────
  Widget _buildBubble(NoteModel note, ThemeData theme, bool isDark) {
    final mine = _isMe(note);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (solo notas ajenas)
          if (!mine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              child: Text(_initials(note.authorName),
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
          ],

          // Burbuja
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: mine
                    ? AppTheme.primary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : theme.cardColor),
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine
                    ? null
                    : Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.07)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre + badge rol (solo notas ajenas)
                  if (!mine) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(note.authorName,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.primary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_roleLabel(note.authorRole),
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Contenido
                  Text(note.content,
                      style: TextStyle(
                          fontSize: 14,
                          color: mine
                              ? Colors.white
                              : theme.textTheme.bodyMedium?.color)),

                  const SizedBox(height: 4),

                  // Pie: hora + indicadores
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Badge transcripción sin confirmar
                      if (!note.audioConfirmed)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('transcripción sin confirmar',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500)),
                        ),
                      if (note.isPending)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 8,
                                height: 8,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text('transcribiendo...',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      if (note.inputMethod == 'voice')
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.mic,
                              size: 11,
                              color: mine
                                  ? Colors.white60
                                  : theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.5)),
                        ),
                        Text(_fmtTime(note.displayTime),
                          style: TextStyle(
                              fontSize: 10,
                              color: mine
                                  ? Colors.white70
                                  : theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.6))),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Avatar propio (lado derecho)
          if (mine) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary,
              child: Text(_initials(widget.currentUser.userName),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Barra de entrada ───────────────────────────────────────────────────────
  Widget _buildInputBar(ThemeData theme, bool isDark, bool busy) {
    final canSend = !busy && !_sending && !_isRecording &&
        _inputCtrl.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform cuando graba
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_amplitudes.length, (i) =>
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 3,
                    height: 24 * _amplitudes[i],
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

          if (!_isRecording && !busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  Icon(
                    _micAvailable ? Icons.phone_android : Icons.cloud_upload,
                    size: 10,
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _micAvailable
                        ? 'Transcripción local'
                        : 'Transcripción en servidor',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Campo de texto
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: 4,
                  minLines: 1,
                  readOnly: _isRecording || _transcribing || _processingAi || _uploadingAudio,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: busy ? null : 'Escribe una nota...',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Botón micrófono
              _InputIconButton(
                icon: _isRecording ? Icons.stop : Icons.mic,
                color: _isRecording
                    ? theme.colorScheme.error
                    : AppTheme.primary,
                tooltip: _isRecording
                    ? 'Detener grabación'
                    : _micAvailable
                        ? 'Grabar nota de voz (Whisper local)'
                        : 'Grabar y enviar al servidor para transcribir',
                onTap: (busy && !_isRecording) ? null : _toggleMic,
              ),
              const SizedBox(width: 6),

              // Botón IA
              _InputIconButton(
                icon: Icons.auto_fix_high,
                color: _aiAvailable ? AppTheme.primary : theme.disabledColor,
                tooltip: _aiAvailable
                  ? 'Limpiar con IA'
                  : 'Selecciona un modelo de limpieza en Configuración IA',
                loading: _processingAi,
                onTap: (!_aiAvailable || busy || _isRecording ||
                    _inputCtrl.text.trim().isEmpty)
                    ? null
                    : _runAi,
              ),
              const SizedBox(width: 6),

              // Botón enviar
              _InputIconButton(
                icon: Icons.send,
                color: Colors.white,
                backgroundColor: canSend
                    ? AppTheme.primary
                    : AppTheme.primary.withValues(alpha: 0.3),
                tooltip: 'Enviar nota',
                loading: _sending,
                onTap: canSend ? _sendNote : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Estados vacío / error ─────────────────────────────────────────────────
  Widget _buildEmpty(ThemeData theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.note_alt_outlined,
            size: 56,
            color: AppTheme.primary.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text('Sin notas aún',
            style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text('Sé el primero en dejar una nota',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color
                    ?.withValues(alpha: 0.5))),
      ],
    ),
  );

  Widget _buildError(ThemeData theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline,
            color: theme.colorScheme.error, size: 48),
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _loadNotes,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );
}

// ── Botón icono para la barra de entrada ──────────────────────────────────────
class _InputIconButton extends StatelessWidget {
  final IconData  icon;
  final Color     color;
  final Color?    backgroundColor;
  final String    tooltip;
  final bool      loading;
  final VoidCallback? onTap;

  const _InputIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.backgroundColor,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color),
                )
              : Icon(icon, color: onTap != null ? color : color.withValues(alpha: 0.4), size: 22),
        ),
      ),
    );
  }
}