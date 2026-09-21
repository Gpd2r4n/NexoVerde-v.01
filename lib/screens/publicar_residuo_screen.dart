import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexoverde/models/residuo_model.dart';
import 'package:nexoverde/services/gemini_service.dart';

class PublicarResiduoScreen extends StatefulWidget {
  const PublicarResiduoScreen({super.key});

  @override
  State<PublicarResiduoScreen> createState() => _PublicarResiduoScreenState();
}

class _PublicarResiduoScreenState extends State<PublicarResiduoScreen> {
  final ImagePicker _picker = ImagePicker();
  final GeminiService _geminiService = GeminiService();

  bool _cargando = false;
  ResiduoModel? _residuoAnalizado;

  // Controladores para la edición del generador
  final TextEditingController _bultosController = TextEditingController(text: '1');
  final TextEditingController _pesoEstimadoController = TextEditingController(text: '20.0');

  Future<void> _capturarFoto() async {
    final XFile? foto = await _picker.pickImage(source: ImageSource.gallery);
    if (foto == null) return;

    setState(() => _cargando = true);

    try {
      final resultado = await _geminiService.analizarFotoResiduo(foto);
      setState(() {
        _residuoAnalizado = resultado;
        if (resultado != null) {
          _pesoEstimadoController.text = resultado.pesoEstimadoKg.toString();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error analizando la imagen: $e')),
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _confirmarDeclaracion() {
    if (_residuoAnalizado == null) return;

    // Actualizar con las cantidades ingresadas manualmente por el generador
    _residuoAnalizado!.cantidadBultos = int.tryParse(_bultosController.text) ?? 1;
    _residuoAnalizado!.pesoEstimadoKg = double.tryParse(_pesoEstimadoController.text) ?? 0.0;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Residuo declarado exitosamente para la Cooperativa!'),
        backgroundColor: Colors.green,
      ),
    );

    // Aquí conectarás con Firestore/Backend para guardar la publicación
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Declarar Residuo B2B'),
        backgroundColor: Colors.green[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _cargando ? null : _capturarFoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(_cargando ? 'Analizando con IA...' : 'Tomar / Subir Foto de Acopio'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
              ),
            ),
            const SizedBox(height: 20),
            if (_cargando) const Center(child: CircularProgressIndicator()),
            if (_residuoAnalizado != null && !_cargando) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Material Detectado: ${_residuoAnalizado!.materialPrincipal}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text('Detalle: ${_residuoAnalizado!.subtipoEspecifico}'),
                      Text('Estado del material: ${_residuoAnalizado!.condicionMaterial}'),
                      const Divider(),
                      const Text(
                        'Declaración de Volumen en Origen',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _bultosController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad de bultos / bolsones',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory_2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pesoEstimadoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Peso Total Estimado (kg)',
                          helperText: 'Ej: 2 bultos de ~20kg cada uno = 40kg',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.scale),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        color: Colors.amber[50],
                        child: Text(
                          'Instrucción: ${_residuoAnalizado!.instruccionesPreparacion}',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _confirmarDeclaracion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text(
                  'Confirmar y Solicitar Recolección',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}