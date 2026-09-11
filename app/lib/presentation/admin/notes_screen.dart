import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../../core/theme/cr_theme.dart';
import '../../data/remote/dto/auth_dto.dart';
import '../../data/remote/notes_service.dart';
import '../widgets/cr_widgets.dart';
import 'register_event_screen.dart';

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
  final ScrollController _scrollCtrl = ScrollController();

  // ── Lista de eventos ──────────────────────────────────────────────────────
  List<NoteModel> _notes = [];
  bool _loading = true;
  String? _error;
  String _filter = 'Todos';
  Timer? _pollTimer;

  // ── Audio player (revisar grabaciones) ────────────────────────────────────
  final Map<String, AudioPlayer> _players = {};
  final Map<String, StreamSubscription<void>> _audioSubs = {};
  final Map<String, bool> _playing = {};
  final Set<String> _played = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _startPollingIfNeeded();
    if (widget.autoOpenRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRegister();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    for (final sub in _audioSubs.values) {
      sub.cancel();
    }
    for (final p in _players.values) {
      p.dispose();
    }
    super.dispose();
  }

  // ── Carga ──────────────────────────────────────────────────────────────────
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

  // ── Registrar evento (vista aparte) ────────────────────────────────────────
  Future<void> _openRegister() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterEventScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
          currentUser: widget.currentUser,
          ward: widget.ward,
          bedNumber: widget.bedNumber,
          primaryDiagnosis: widget.primaryDiagnosis,
        ),
      ),
    );
    if (saved == true && mounted) {
      _loadNotes();
      _startPollingIfNeeded();
    }
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
    _audioSubs[note.id] = player.onPlayerComplete.listen((_) {
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

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
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
                onTap: _openRegister,
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

}
