import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/notes_service.dart';
import '../../data/services/whisper_service.dart';
import '../settings/ai_settings_screen.dart'; // enums WhisperModel / LlmModel
import '../widgets/cr_widgets.dart';

enum _AudioFormState { idle, recording, ready, processing }
enum _SheetStage { form, review, done }

class NotesScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final LoginResponseDto currentUser;
  final String? ward;
  final String? bedNumber;
  final String? admissionDate;
  final String? primaryDiagnosis;
  final bool autoOpenRegister;

  const NotesScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.currentUser,
    this.ward,
    this.bedNumber,
    this.admissionDate,
    this.primaryDiagnosis,
    this.autoOpenRegister = false,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NotesService _service = NotesService();
  final WhisperService _whisperService = WhisperService();
  final ScrollController _scrollCtrl = ScrollController();

  // ── Estado AI (SharedPreferences) ─────────────────────────────────────────
  WhisperModel _whisperModel = WhisperModel.none;
  LlmModel _llmModel = LlmModel.none;
  bool _whisperDownloaded = false;
  String _modelsPath = '';
  bool _processingAi = false;

  bool get _micAvailable =>
      _whisperModel != WhisperModel.none && _whisperDownloaded;
  bool get _aiAvailable => _llmModel != LlmModel.none;

  // ── Lista de eventos ──────────────────────────────────────────────────────
  List<NoteModel> _notes = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _filter = 'Todos';

  // ── Micrófono ─────────────────────────────────────────────────────────────
  bool _isRecording = false;
  _AudioFormState _audioForm = _AudioFormState.idle;
  File? _pendingAudioFile;
  DateTime? _recordedAt;
  int _seconds = 0;
  int _durationSecs = 0;
  Timer? _timeTimer;
  Timer? _waveformTimer;
  Timer? _pollTimer;
  final List<double> _amplitudes = List.filled(24, 0.1);

  // ── Sheet de registro ─────────────────────────────────────────────────────
  bool _sheetOpen = false;
  String _sheetMode = 'audio'; // 'audio' | 'text'
  _SheetStage _sheetStage = _SheetStage.form;
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _reviewCtrl = TextEditingController();
  NoteModel? _doneNote;
  bool _doneVoice = false;

  // ── Audio player (revisar grabaciones) ────────────────────────────────────
  final Map<String, AudioPlayer> _players = {};
  final Map<String, StreamSubscription<void>> _audioSubs = {};
  final Map<String, bool> _playing = {};
  final Set<String> _played = {};

  @override
  void initState() {
    super.initState();
    _loadAiState();
    _loadNotes();
    _startPollingIfNeeded();
    if (widget.autoOpenRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSheet();
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _reviewCtrl.dispose();
    _scrollCtrl.dispose();
    _timeTimer?.cancel();
    _waveformTimer?.cancel();
    _pollTimer?.cancel();
    for (final sub in _audioSubs.values) {
      sub.cancel();
    }
    for (final p in _players.values) {
      p.dispose();
    }
    _whisperService.cancelRecording().catchError((_) => null);
    super.dispose();
  }

  // ── Carga ──────────────────────────────────────────────────────────────────
  Future<void> _loadAiState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsDir = await getApplicationDocumentsDirectory();
      final path = '${documentsDir.path}/models';
      final modelsDir = Directory(path);
      if (!modelsDir.existsSync()) {
        modelsDir.createSync(recursive: true);
      }

      final whisperIndex = prefs.getInt('whisper_model') ?? 0;
      final wModel = (whisperIndex >= 0 &&
              whisperIndex < WhisperModel.values.length)
          ? WhisperModel.values[whisperIndex]
          : WhisperModel.none;

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
    } catch (_) {}
  }

  Future<void> _loadNotes() async {
    final showInitialLoading = _notes.isEmpty;
    setState(() {
      if (showInitialLoading) _loading = true;
      _error = null;
    });
    try {
      final notes = await _service.getNotes(widget.patientId);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
      _scrollToBottom();
      _startPollingIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (_notes.any((n) => n.isPending)) {
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
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

  List<NoteModel> get _filteredNotes {
    switch (_filter) {
      case 'Textos':
        return _notes.where((n) => n.inputMethod != 'voice').toList();
      case 'Voz':
        return _notes.where((n) => n.inputMethod == 'voice').toList();
      case 'Pendientes':
        return _notes.where((n) => n.isPending).toList();
      default:
        return _notes;
    }
  }

  // ── Sheet: abrir / cerrar ──────────────────────────────────────────────────
  void _openSheet() {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildSheet(),
    ).whenComplete(() {
      if (mounted) _resetSheet();
    });
  }

  Future<void> _closeSheet() async {
    if (_isRecording) {
      _waveformTimer?.cancel();
      _timeTimer?.cancel();
      try {
        await _whisperService.stopAndGetFile();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _audioForm = _AudioFormState.idle;
      });
    }
    if (mounted) Navigator.pop(context);
  }

  void _resetSheet() {
    _textCtrl.clear();
    _reviewCtrl.clear();
    _pendingAudioFile?.delete().catchError((_) => null);
    setState(() {
      _sheetOpen = false;
      _sheetMode = 'audio';
      _sheetStage = _SheetStage.form;
      _audioForm = _AudioFormState.idle;
      _pendingAudioFile = null;
      _recordedAt = null;
      _seconds = 0;
      _durationSecs = 0;
      _doneNote = null;
      _doneVoice = false;
      for (var i = 0; i < _amplitudes.length; i++) {
        _amplitudes[i] = 0.1;
      }
    });
  }

  // ── Grabación ──────────────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Permiso de micrófono denegado'),
              backgroundColor: CR.red),
        );
      }
      return;
    }
    _pendingAudioFile?.delete().catchError((_) => null);
    _pendingAudioFile = null;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _whisperService.startRecording();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('No se pudo iniciar el micrófono'),
              backgroundColor: CR.red),
        );
      }
      return;
    }
    if (!mounted) {
      _whisperService.cancelRecording().catchError((_) => null);
      return;
    }
    _recordedAt = DateTime.now();
    setState(() {
      _isRecording = true;
      _audioForm = _AudioFormState.recording;
      _seconds = 0;
    });
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _amplitudes.length; i++) {
          _amplitudes[i] = math.max(0.12, math.Random().nextDouble());
        }
      });
    });
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = _seconds + 1);
    });
  }

  Future<void> _stopRecording() async {
    _waveformTimer?.cancel();
    _timeTimer?.cancel();
    _durationSecs = _seconds;
    File? audioFile;
    try {
      audioFile = await _whisperService.stopAndGetFile();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _seconds = 0;
      for (var i = 0; i < _amplitudes.length; i++) {
        _amplitudes[i] = 0.1;
      }
      if (audioFile != null) {
        _pendingAudioFile = audioFile;
        _audioForm = _AudioFormState.ready;
      } else {
        _audioForm = _AudioFormState.idle;
      }
    });
    if (audioFile == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('No se pudo guardar la grabación'),
            backgroundColor: CR.red),
      );
    }
  }

  String _formatClock(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Procesamiento (local → review, servidor → publish) ───────────────────
  Future<void> _processRecording() async {
    final file = _pendingAudioFile;
    if (file == null) return;
    setState(() => _audioForm = _AudioFormState.processing);

    if (_micAvailable) {
      final folder = _whisperModel == WhisperModel.base
          ? 'whisper-base'
          : 'whisper-small';
      final result = await _whisperService.transcribeFromPath(
          file.path, '$_modelsPath/$folder');
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      if (!mounted) return;
      final text = (result ?? '').trim();
      _reviewCtrl.text = text.startsWith('Error') ? '' : text;
      setState(() {
        _audioForm = _AudioFormState.ready;
        _sheetStage = _SheetStage.review;
      });
    } else {
      try {
        final note = await _service.uploadAudio(
          patientId: widget.patientId,
          authorId: widget.currentUser.userId,
          recordedAt: (_recordedAt ?? DateTime.now()).toIso8601String(),
          audioFile: file,
        );
        if (!mounted) return;
        setState(() {
          _notes.add(note);
          _audioForm = _AudioFormState.ready;
          _sheetStage = _SheetStage.done;
          _doneNote = note;
          _doneVoice = true;
        });
        _scrollToBottom();
        _startPollingIfNeeded();
      } catch (e) {
        if (!mounted) return;
        setState(() => _audioForm = _AudioFormState.ready);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: CR.red),
        );
      }
    }
  }

  // ── Publicar ───────────────────────────────────────────────────────────────
  Future<NoteModel?> _sendNote({
    required String text,
    required bool voice,
    required String transcriptionSource,
  }) async {
    setState(() => _sending = true);
    try {
      final note = await _service.createNote(
        patientId: widget.patientId,
        authorId: widget.currentUser.userId,
        content: text,
        inputMethod: voice ? 'voice' : 'text',
        transcriptionSource: transcriptionSource,
        // true cuando el usuario validó el texto; false queda para
        // transcripciones de servidor sin revisión del usuario
        audioConfirmed: true,
      );
      if (!mounted) return null;
      setState(() => _notes.add(note));
      _scrollToBottom();
      _startPollingIfNeeded();
      return note;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: CR.red),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _publishReview() async {
    final text = _reviewCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final note = await _sendNote(
      text: text,
      voice: true,
      transcriptionSource: 'auto_whisper',
    );
    if (note != null && mounted) {
      setState(() {
        _sheetStage = _SheetStage.done;
        _audioForm = _AudioFormState.ready;
        _doneNote = note;
        _doneVoice = true;
      });
    }
  }

  Future<void> _publishText() async {
    final text = _textCtrl.text.trim();
    if (text.length < 20 || _sending) return;
    final note =
        await _sendNote(text: text, voice: false, transcriptionSource: 'manual');
    if (note != null && mounted) {
      setState(() {
        _sheetStage = _SheetStage.done;
        _doneNote = note;
        _doneVoice = false;
      });
    }
  }

  // ── IA: limpieza simulada (revisión) ──────────────────────────────────────
  Future<void> _runAi() async {
    if (_reviewCtrl.text.trim().isEmpty) return;
    setState(() => _processingAi = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _processingAi = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Limpieza con IA pendiente de integrar el modelo')),
    );
  }

  // ── Audio player ───────────────────────────────────────────────────────────
  Future<void> _toggleAudio(NoteModel note) async {
    final isPlaying = _playing[note.id] ?? false;

    if (isPlaying) {
      try {
        await _players[note.id]?.stop();
      } catch (_) {}
      if (!mounted) return;
      _audioSubs[note.id]?.cancel();
      _audioSubs.remove(note.id);
      setState(() => _playing[note.id] = false);
      return;
    }

    for (final entry in _players.entries) {
      if (entry.key != note.id) {
        try {
          await entry.value.stop();
        } catch (_) {}
        _playing[entry.key] = false;
        _audioSubs[entry.key]?.cancel();
        _audioSubs.remove(entry.key);
      }
    }
    if (!mounted) return;

    final player = _players.putIfAbsent(note.id, () => AudioPlayer());
    final url = _service.audioUrl(note.id);

    _audioSubs[note.id]?.cancel();
    _audioSubs[note.id] = player.onPlayerComplete.listen<void>((_) {
      if (!mounted) return;
      setState(() {
        _playing[note.id] = false;
        _played.add(note.id);
      });
    });

    try {
      await player.play(UrlSource(url));
    } catch (e) {
      _audioSubs[note.id]?.cancel();
      _audioSubs.remove(note.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo reproducir el audio: $e'),
              backgroundColor: CR.red),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _playing[note.id] = true);
  }

  Future<void> _confirmTranscription(NoteModel note) async {
    try {
      await _service.confirmTranscription(note.id);
      await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: CR.red),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _roleLabel(String r) => switch (r) {
        'admin' => 'Administrador',
        'doctor' => 'Médico',
        'nurse' => 'Enfermería',
        'tech' => 'Equipo Ampliado',
        _ => r,
      };

  String _fmtTime(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final date = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final diff = today.difference(date).inDays;

      final time = '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
      if (diff == 0) return time;
      if (diff == 1) return 'Ayer $time';
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} $time';
    } catch (_) {
      return raw;
    }
  }

  String _timeOnly(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _patientLabel() {
    final buffer = StringBuffer(widget.patientName);
    if (widget.bedNumber != null && widget.bedNumber!.isNotEmpty) {
      buffer.write(' · Cama ${widget.bedNumber}');
    }
    if (widget.ward != null && widget.ward!.isNotEmpty) {
      buffer.write(' · ${widget.ward}');
    }
    return buffer.toString();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = CRTokens.of(context);
    const filters = ['Todos', 'Textos', 'Voz', 'Pendientes'];

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                CRNavBar(
                  onBack: () => Navigator.pop(context),
                  right: IconButton(
                    icon: Icon(Icons.refresh, size: 20, color: t.textSecondary),
                    onPressed: _loadNotes,
                  ),
                ),
                _buildPatientBanner(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bitácora',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: t.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const SizedBox(
                            width: 6,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: CR.mintDark, shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Hoy · Turno 08:00–16:00',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: CR.mintDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Filtros
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 20, top: 14),
                    children: filters
                        .map((f) => CRFilterChip(
                              label: f,
                              selected: _filter == f,
                              onTap: () =>
                                  setState(() => _filter = f),
                            ))
                        .toList(),
                  ),
                ),
                // Lista
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _buildError(t)
                          : _filteredNotes.isEmpty
                              ? _buildEmpty(t)
                              : ListView.builder(
                                  controller: _scrollCtrl,
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 16, 90),
                                  itemCount: _filteredNotes.length,
                                  itemBuilder: (_, i) =>
                                      _buildEventCard(_filteredNotes[i], t),
                                ),
                ),
              ],
            ),
            // Botón flotante "Registrar evento"
            Positioned(
              right: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: _openSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF72EDD1), Color(0xFF29B88F)]),
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: CR.mintDark.withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: CR.mintInk),
                      SizedBox(width: 6),
                      Text(
                        'Registrar evento',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CR.mintInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Banner del paciente ────────────────────────────────────────────────────
  Widget _buildPatientBanner() {
    final metaParts = <String>[
      if (widget.bedNumber != null && widget.bedNumber!.isNotEmpty)
        'Cama ${widget.bedNumber}',
      if (widget.ward != null && widget.ward!.isNotEmpty) widget.ward!,
      if (widget.primaryDiagnosis != null &&
          widget.primaryDiagnosis!.isNotEmpty)
        widget.primaryDiagnosis!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CR.mintSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CRCircleAvatar(
              initials: _initials(widget.patientName),
              size: 34,
              bg: CR.mintDark,
              fg: Colors.white,
              fontSize: 12,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CR.mintInk),
                  ),
                  if (metaParts.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      metaParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: CR.mintInk.withValues(alpha: 0.6)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tarjeta de evento (timeline) ──────────────────────────────────────────
  Widget _buildEventCard(NoteModel note, CRTokens t) {
    final category = note.inputMethod == 'voice' ? 'Voz' : 'Nota clínica';
    final showAudioChips =
        note.inputMethod == 'voice' && !note.audioConfirmed;

    return CREventCard(
      time: _fmtTime(
          note.displayTime.isNotEmpty ? note.displayTime : note.createdAt),
      role: _roleLabel(note.authorRole),
      category: category,
      content: note.content,
      pending: note.isPending,
      author: note.authorName,
      footer: (showAudioChips || note.inputMethod == 'voice')
          ? Row(
              children: [
                if (note.inputMethod == 'voice')
                  Icon(Icons.mic, size: 12, color: t.textTertiary),
                const Spacer(),
                if (showAudioChips) ..._audioChips(note, t),
              ],
            )
          : null,
    );
  }

  List<Widget> _audioChips(NoteModel note, CRTokens t) {
    final isPlaying = _playing[note.id] ?? false;
    final hasBeenPlayed = _played.contains(note.id);
    final green = const Color(0xFF34C759);
    return [
      GestureDetector(
        onTap: () => _toggleAudio(note),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: CR.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: CR.orange.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 11, color: CR.orange),
              const SizedBox(width: 3),
              Text(
                'escuchar',
                style: TextStyle(
                    fontSize: 10,
                    color: CR.orange,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      GestureDetector(
        onTap: hasBeenPlayed ? () => _confirmTranscription(note) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: hasBeenPlayed
                ? green.withValues(alpha: 0.12)
                : t.chipBg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: hasBeenPlayed
                    ? green.withValues(alpha: 0.4)
                    : t.separator),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check,
                  size: 11,
                  color: hasBeenPlayed ? green : t.textTertiary),
              const SizedBox(width: 3),
              Text(
                'confirmar',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: hasBeenPlayed ? green : t.textTertiary),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── Estados vacío / error ─────────────────────────────────────────────────
  Widget _buildEmpty(CRTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off_rounded,
              size: 52, color: t.textTertiary),
          const SizedBox(height: 10),
          Text(
            'Sin eventos registrados',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Usa "Registrar evento" para crear el primero',
            style: TextStyle(fontSize: 13, color: t.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildError(CRTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: CR.red, size: 44),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _error ?? 'Error al cargar la bitácora',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: CR.red),
            ),
          ),
          const SizedBox(height: 16),
          CRPrimaryButton(
            label: 'Reintentar',
            height: 48,
            onPressed: _loadNotes,
          ),
        ],
      ),
    );
  }

  // ── Sheet de registro ──────────────────────────────────────────────────────
  Widget _buildSheet() {
    final t = CRTokens.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: t.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Encabezado
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text(
                  'Registrar evento',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: t.textPrimary),
                ),
                const Spacer(),
                InkWell(
                  onTap: _closeSheet,
                  borderRadius: BorderRadius.circular(8),
                  child:
                      Padding(padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 20, color: t.textTertiary)),
                ),
              ],
            ),
          ),
          // Contexto del paciente
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CRPatientContextPill(label: _patientLabel()),
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _sheetStage == _SheetStage.done
                ? _buildDone(t)
                : _sheetStage == _SheetStage.review
                    ? _buildReview(t)
                    : _buildForm(t),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Form (Audio | Texto) ───────────────────────────────────────────────────
  Widget _buildForm(CRTokens t) {
    final segmented = Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.chipBg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final m in const ['audio', 'text'])
            Expanded(
              child: GestureDetector(
                onTap: _isRecording
                    ? null
                    : () => setState(() {
                          _sheetMode = m;
                          _sheetStage = _SheetStage.form;
                        }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: _sheetMode == m ? t.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _sheetMode == m ? t.cardShadow : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        m == 'audio' ? Icons.mic : Icons.text_fields,
                        size: 15,
                        color: _sheetMode == m
                            ? CR.mintDark
                            : t.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        m == 'audio' ? 'Audio' : 'Texto',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _sheetMode == m
                                ? t.textPrimary
                                : t.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      children: [
        segmented,
        const SizedBox(height: 16),
        Expanded(
          child:
              _sheetMode == 'audio' ? _buildAudioForm() : _buildTextForm(t),
        ),
      ],
    );
  }

  Widget _buildAudioForm() {
    const panel = Color(0xFF0A0A0C);
    final recording = _audioForm == _AudioFormState.recording;
    final ready = _audioForm == _AudioFormState.ready;
    final processing = _audioForm == _AudioFormState.processing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Estado
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: recording
                      ? CR.red.withValues(alpha: 0.3)
                      : ready
                          ? CR.mint.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: recording
                            ? const Color(0xFFFF6B6B)
                            : ready
                                ? CR.mint
                                : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      recording
                          ? 'Grabando'
                          : ready
                              ? 'Grabación lista'
                              : processing
                                  ? 'Procesando…'
                                  : 'Listo para grabar',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: recording
                              ? const Color(0xFFFF9B9B)
                              : ready
                                  ? CR.mint
                                  : Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
            Spacer(flex: 2),

            // Reloj / spinner
            Center(
              child: processing
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child:
                          CircularProgressIndicator(strokeWidth: 3, color: CR.mint))
                  : ready
                      ? Column(
                          children: [
                            Text(
                              _formatClock(_durationSecs),
                              style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: CR.mint),
                            ),
                            const SizedBox(height: 4),
                            Text('duración',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white54)),
                          ],
                        )
                      : Text(
                          _formatClock(recording ? _seconds : 0),
                          style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: recording
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35)),
                        ),
            ),
            const SizedBox(height: 18),

            // Waveform
            SizedBox(
              height: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_amplitudes.length, (i) {
                  final on = recording || ready;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 3,
                      height: on ? 8 + 20 * _amplitudes[i] : 4,
                      decoration: BoxDecoration(
                        color: recording
                            ? CR.mint
                            : on
                                ? CR.mint.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),

            // Botón principal
            if (processing)
              Text(
                'Transcribiendo y preparando el registro…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              )
            else if (ready)
              Row(
                children: [
                  _MiniCircleButton(
                    icon: Icons.replay_rounded,
                    onTap: _toggleRecording,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: CRPrimaryButton(
                      label: 'Procesar registro',
                      height: 52,
                      onPressed: _processRecording,
                    ),
                  ),
                  const SizedBox(width: 14),
                  _MiniCircleButton(icon: Icons.delete_outline_rounded,
                      onTap: _discardRecording),
                ],
              )
            else
              Center(
                child: _BigRecordButton(
                  active: recording,
                  onTap: _toggleRecording,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              ready
                  ? 'Revisa o procesa la transcripción del audio'
                  : recording
                      ? 'Toca el botón para detener'
                      : 'Acerca el micrófono y pulsa para grabar',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(
                      alpha: recording || processing ? 0.75 : 0.45)),
            ),
          ],
        ),
      ),
    );
  }

  void _discardRecording() {
    _pendingAudioFile?.delete().catchError((_) => null);
    setState(() {
      _pendingAudioFile = null;
      _audioForm = _AudioFormState.idle;
    });
  }

  Widget _buildTextForm(CRTokens t) {
    final len = _textCtrl.text.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: t.field,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: len > 0
                      ? CR.mintDark.withValues(alpha: 0.5)
                      : Colors.transparent,
                  width: len > 0 ? 1.4 : 1,
                ),
              ),
              child: TextField(
                controller: _textCtrl,
                maxLines: 8,
                minLines: 8,
                maxLength: 1000,
                style: TextStyle(fontSize: 15, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Describe el acontecimiento clínico…',
                  hintStyle:
                      TextStyle(fontSize: 15, color: t.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Text('$len/1000',
                style: TextStyle(fontSize: 12, color: t.textTertiary)),
          ),
          const SizedBox(height: 10),
          CRPrimaryButton(
            label: len < 20 ? 'Escribe al menos 20 caracteres' : 'Continuar',
            loading: _sending,
            onPressed: len < 20 ? null : _publishText,
          ),
        ],
      ),
    );
  }

  // ── Review (transcripción sugerida) ───────────────────────────────────────
  Widget _buildReview(CRTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: CRSectionLabel(text: 'Transcripción sugerida')),
              if (_aiAvailable)
                _MiniCircleButton(
                  icon: Icons.auto_fix_high_rounded,
                  loading: _processingAi,
                  onTap: _runAi,
                  light: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const CRAIBadge(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La IA sugiere, tú validas. Revisa antes de publicar.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: t.field,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.separator),
              ),
              child: TextField(
                controller: _reviewCtrl,
                maxLines: 10,
                minLines: 10,
                style:
                    TextStyle(fontSize: 15, height: 1.45, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'No se pudo obtener una transcripción clara',
                  hintStyle: TextStyle(fontSize: 15, color: t.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          CRPrimaryButton(
            label: 'Confirmar y publicar',
            loading: _sending,
            onPressed:
                _reviewCtrl.text.trim().isEmpty ? null : _publishReview,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () =>
                setState(() => _sheetStage = _SheetStage.form),
            child: const Text(
              'Descartar evento',
              style: TextStyle(fontSize: 14, color: CR.red),
            ),
          ),
        ],
      ),
    );
  }

  // ── Done (evento publicado) ────────────────────────────────────────────────
  Widget _buildDone(CRTokens t) {
    final note = _doneNote;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: CR.mintSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 38, color: CR.mintDark),
            ),
            const SizedBox(height: 16),
            Text(
              'Evento publicado',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: t.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _doneVoice
                  ? 'El registro de voz fue incorporado a la bitácora'
                  : 'El texto fue incorporado a la bitácora',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.textSecondary),
            ),
            if (note != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.field,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _doneRow(t, 'Hora',
                        _timeOnly(note.displayTime.isNotEmpty
                            ? note.displayTime
                            : note.createdAt)),
                    _doneRow(t, 'Autor', note.authorName),
                    _doneRow(
                        t, 'Categoría', _doneVoice ? 'Voz' : 'Nota clínica'),
                    const Divider(height: 12),
                    Text(
                      note.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 14, height: 1.4, color: t.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            CRPrimaryButton(
              label: 'Volver a la bitácora',
              onPressed: _closeSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneRow(CRTokens t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Botón circular grande de grabación ───────────────────────────────────────
class _BigRecordButton extends StatelessWidget {
  final bool active;
  final VoidCallback? onTap;

  const _BigRecordButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? CR.red : CR.mint,
          boxShadow: [
            BoxShadow(
              color: active
                  ? CR.red.withValues(alpha: 0.45)
                  : CR.mintDark.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: active
              ? Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                )
              : const Icon(Icons.mic, size: 36, color: CR.mintInk),
        ),
      ),
    );
  }
}

// ── Botón circular pequeño (volver a grabar / descartar / IA) ────────────────
class _MiniCircleButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final bool light;

  const _MiniCircleButton(
      {required this.icon,
      required this.onTap,
      this.loading = false,
      this.light = false});

  @override
  Widget build(BuildContext context) {
    final tint = light ? CR.mintDark : Colors.white70;
    final bg =
        light ? CR.mintSoft : Colors.white.withValues(alpha: 0.08);
    final border =
        light ? CR.mintDark.withValues(alpha: 0.4) : Colors.white24;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(color: border),
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tint),
                ),
              )
            : Icon(icon ?? Icons.circle, size: 20, color: tint),
      ),
    );
  }
}
