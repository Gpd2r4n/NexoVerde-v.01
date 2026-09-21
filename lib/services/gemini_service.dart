import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../models/residuo_model.dart';

class GeminiService {
  // Coloca tu API Key válida obtenida de Google AI Studio
  static const String _apiKey = 'AQ.Ab8RN6I0pFPjTX-kbk8LyTXaTWvWwehs55AR4peVqegDKhYujg';

  // Modelos oficiales de respaldo si el principal está saturado (503)
  final List<String> _modelosDisponibles = [
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-flash-latest',
  ];

  Future<ResiduoModel?> analizarFotoResiduo(XFile foto) async {
    try {
      // Lectura en memoria segura para Web, Android e iOS
      final Uint8List bytes = await foto.readAsBytes();
      final String base64Image = base64Encode(bytes);

      final prompt = '''
Eres un experto ambiental para la app "NexoVerde".
Analiza la imagen y devuelve ÚNICAMENTE un objeto JSON estricto con:
{
  "material_principal": "Ej: Cartón, Plástico PET, Vidrio",
  "subtipo_especifico": "Descripción detallada",
  "condicion_material": "Ej: A granel, Fardado",
  "peso_estimado_kg": 0.5,
  "instrucciones_preparacion": "Pasos breves de limpieza o compactado",
  "contenedor_destino": "Color de contenedor sugerido"
}
IMPORTANTE: No incluyas markdown, saludos, ni comillas invertidas.
''';

      for (String modelo in _modelosDisponibles) {
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$modelo:generateContent?key=$_apiKey',
          );

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": prompt},
                    {
                      "inline_data": {
                        "mime_type": "image/jpeg",
                        "data": base64Image
                      }
                    }
                  ]
                }
              ]
            }),
          );

          if (response.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(response.body);
            final String textoGenerado =
                data['candidates'][0]['content']['parts'][0]['text'];

            String textoLimpio = textoGenerado
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();

            return ResiduoModel.fromJson(jsonDecode(textoLimpio));
          } else if (response.statusCode == 503) {
            print('⚠️ Modelo $modelo saturado (503). Intentando respaldo...');
            continue;
          } else {
            print('Error en servidor Google ($modelo): ${response.body}');
          }
        } catch (e) {
          print('Error de conexión con el modelo $modelo: $e');
        }
      }
    } catch (e) {
      print('Error procesando imagen: $e');
    }
    return null;
  }
}