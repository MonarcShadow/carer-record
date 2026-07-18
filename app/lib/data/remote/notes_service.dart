import 'dart:convert';
import 'package:http/http.dart' as http;
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
  final String createdAt;

  NoteModel({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.inputMethod,
    required this.transcriptionSource,
    required this.audioConfirmed,
    required this.createdAt,
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
    createdAt:            j['created_at']            as String? ?? '',
  );
}

class NotesService {
  final String _base = '${AppConfig.baseUrl}/api/v1/notes';

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
}