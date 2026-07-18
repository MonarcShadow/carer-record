import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../core/config.dart';

class NoteModel {
  final String id;
  final String content;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String inputMethod;
  final String transcriptionSource;
  final bool   audioConfirmed;
  final String audioStatus;    // ← nuevo: 'pending','processing','done','error', o ''
  final String displayTime;    // ← nuevo: recorded_at ?? created_at
  final String createdAt;
  final String? audioPath;   // ← nuevo


  NoteModel({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.inputMethod,
    required this.transcriptionSource,
    required this.audioConfirmed,
    required this.audioStatus,
    required this.displayTime,
    required this.createdAt,
    required this.audioPath,

  });

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
    id:                   j['id']                    as String? ?? '',
    content:              j['content']               as String? ?? '',
    authorId:             j['author_id']             as String? ?? '',
    authorName:           j['author_name']           as String? ?? '',
    authorRole:           j['author_role']           as String? ?? '',
    inputMethod:          j['input_method']          as String? ?? 'text',
    transcriptionSource:  j['transcription_source']  as String? ?? 'manual',
    audioConfirmed:       (j['audio_confirmed'] as int? ?? 1) == 1,
    audioStatus:          j['audio_status']          as String? ?? '',
    displayTime:          j['display_time']          as String? ?? '',
    createdAt:            j['created_at']            as String? ?? '',
    audioPath:            j['audio_path']            as String?,
  );

  bool get isPending => audioStatus == 'pending' || audioStatus == 'processing';
}

class NotesService {
  final String _base = '${AppConfig.baseUrl}/api/v1/notes';

  String audioUrl(String noteId) => '$_base/audio/$noteId';

  Future<void> confirmTranscription(String noteId) async {
    final res = await http.patch(Uri.parse('$_base/$noteId/confirm'));
    if (res.statusCode != 200) {
      throw Exception('Error al confirmar transcripción');
    }
  }

  Future<List<NoteModel>> getNotes(String patientId) async {
    final res = await http.get(Uri.parse('$_base/$patientId'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(res.bodyBytes));
      return data.map((e) => NoteModel.fromJson(e)).toList();
    }
    throw Exception('Error al cargar notas');
  }

  Future<NoteModel> createNote({
    required String patientId,
    required String authorId,
    required String content,
    String inputMethod         = 'text',
    String transcriptionSource = 'manual',
    bool   audioConfirmed      = true,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'patient_id':           patientId,
        'author_id':            authorId,
        'content':              content,
        'input_method':         inputMethod,
        'transcription_source': transcriptionSource,
        'audio_confirmed':      audioConfirmed,
      }),
    );
    if (res.statusCode == 201) {
      return NoteModel.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    final detail = jsonDecode(res.body)['detail'] ?? 'Error al crear nota';
    throw Exception(detail);
  }

  Future<NoteModel> uploadAudio({
    required String patientId,
    required String authorId,
    required String recordedAt,   // ISO 8601
    required File   audioFile,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/audio'));
    req.fields['patient_id']  = patientId;
    req.fields['author_id']   = authorId;
    req.fields['recorded_at'] = recordedAt;
    req.files.add(await http.MultipartFile.fromPath(
      'audio_file',
      audioFile.path,
      contentType: MediaType('audio', 'wav'),
    ));
    final streamed = await req.send();
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode == 201) {
      return NoteModel.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    final detail = jsonDecode(res.body)['detail'] ?? 'Error al subir audio';
    throw Exception(detail);
  }
}