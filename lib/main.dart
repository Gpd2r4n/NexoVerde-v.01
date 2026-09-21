import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'services/gemini_service.dart';
import 'models/residuo_model.dart';

/// Lógica Matemática de Análisis de Ciclo de Vida (ACV) según IPCC / EPA
class CalculadoraImpactoACV {
  static const Map<String, Map<String, double>> factoresPorMaterial = {
    'Cartón / Papel': {'disposicion': 1.10, 'sustitucion': 0.75},
    'Plástico PET': {'disposicion': 0.85, 'sustitucion': 1.00},
    'Plástico PEAD/PEBD': {'disposicion': 0.70, 'sustitucion': 0.80},
    'Aluminio': {'disposicion': 1.80, 'sustitucion': 7.00},
    'Vidrio': {'disposicion': 0.10, 'sustitucion': 0.28},
    'Madera': {'disposicion': 0.35, 'sustitucion': 0.40},
  };

  static double calcularCo2Neto({
    required String material,
    required double pesoKg,
    double distanciaKm = 12.0,
    double feTransporte = 0.00025,
  }) {
    final factores = factoresPorMaterial.entries
        .firstWhere(
          (entry) => material.toLowerCase().contains(entry.key.toLowerCase().split(' ')[0]),
          orElse: () => const MapEntry('Otros', {'disposicion': 0.50, 'sustitucion': 0.50}),
        )
        .value;

    final feDisposicion = factores['disposicion']!;
    final feSustitucion = factores['sustitucion']!;

    double ahorroBruto = pesoKg * (feDisposicion + feSustitucion);
    double emisionLogistica = pesoKg * distanciaKm * feTransporte;
    double impactoNeto = ahorroBruto - emisionLogistica;

    return impactoNeto > 0 ? impactoNeto : 0.0;
  }

  static int calcularEcoPuntos(double co2Neto) {
    return co2Neto.round();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCkreZapG452K4eLVM9-OGwch4wncaldDQ",
        appId: "1:760643955437:web:6db2ffdd14c293ed74fae4",
        messagingSenderId: "760643955437",
        projectId: "proyecto-nexoverde01",
        authDomain: "proyecto-nexoverde01.firebaseapp.com",
        storageBucket: "proyecto-nexoverde01.firebasestorage.app",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const NexoVerdeApp());
}

void mostrarDialogoRecuperarPassword(BuildContext context) {
  final TextEditingController emailController = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, ingresa tu correo.')),
                );
                return;
              }

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Correo de recuperación enviado. Revisa tu bandeja de entrada.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } on FirebaseAuthException catch (e) {
                String mensaje = 'Error al enviar el correo.';
                if (e.code == 'user-not-found') {
                  mensaje = 'No hay ningún usuario registrado con este correo.';
                } else if (e.code == 'invalid-email') {
                  mensaje = 'El correo ingresado no es válido.';
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mensaje),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      );
    },
  );
}

class NexoVerdeApp extends StatelessWidget {
  const NexoVerdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexoVerde',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(snapshot.data!.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
              final rol = userData?['rol'] ?? 'generador';

              if (rol == 'recuperador') {
                return const MainNavigationRecuperador();
              } else {
                return const MainNavigationGenerador();
              }
            },
          );
        }

        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cuitController = TextEditingController();
  final _nombreOrgController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _direccionController = TextEditingController();
  
  // Generador extra
  String _rubro = 'Gastronómico';
  String _categoriaGenerador = 'Mediano Generador';
  
  // Recuperador extra
  final _matriculaInaesController = TextEditingController();
  String _tipoVehiculo = 'Camioneta / Furgón';

  String _rolSeleccionado = 'generador';
  bool _esLogin = true;
  bool _cargando = false;

  Future<void> _autenticar() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, completa los campos de correo y contraseña.')),
      );
      return;
    }

    if (!_esLogin && (_cuitController.text.trim().isEmpty || _nombreOrgController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, completa el CUIT y Nombre de la Organización.')),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      if (_esLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      } else {
        UserCredential creds = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        Map<String, dynamic> datosUsuario = {
          'email': email,
          'cuit': _cuitController.text.trim(),
          'nombre_organizacion': _nombreOrgController.text.trim(),
          'telefono_whatsapp': _whatsappController.text.trim(),
          'direccion_acopio': _direccionController.text.trim(),
          'rol': _rolSeleccionado,
          'fecha_registro': FieldValue.serverTimestamp(),
        };

        if (_rolSeleccionado == 'generador') {
          datosUsuario['rubro'] = _rubro;
          datosUsuario['categoria_generador'] = _categoriaGenerador;
        } else {
          datosUsuario['matricula_inaes'] = _matriculaInaesController.text.trim();
          datosUsuario['tipo_vehiculo'] = _tipoVehiculo;
        }

        await FirebaseFirestore.instance.collection('usuarios').doc(creds.user!.uid).set(datosUsuario);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Error de autenticación'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Icon(Icons.eco, size: 80, color: Colors.green.shade700),
                const SizedBox(height: 12),
                Text('NexoVerde', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                const SizedBox(height: 6),
                const Text('Plataforma B2B de Economía Circular', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 30),
                TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo Electrónico', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())),
                if (!_esLogin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nombreOrgController,
                    decoration: const InputDecoration(labelText: 'Nombre de Empresa / Cooperativa', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _cuitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CUIT / Identificación Fiscal', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _whatsappController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono WhatsApp (Contacto Directo)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _direccionController,
                    decoration: const InputDecoration(labelText: 'Dirección Base en Corrientes', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tipo de Organización:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('Empresa Generadora'),
                    subtitle: const Text('Tengo residuos para reciclar y medir mi impacto ESG'),
                    value: 'generador',
                    groupValue: _rolSeleccionado,
                    onChanged: (val) => setState(() => _rolSeleccionado = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Cooperativa / Recolector'),
                    subtitle: const Text('Busco retirar y clasificar residuos en mi zona'),
                    value: 'recuperador',
                    groupValue: _rolSeleccionado,
                    onChanged: (val) => setState(() => _rolSeleccionado = val!),
                  ),
                  const SizedBox(height: 12),
                  if (_rolSeleccionado == 'generador') ...[
                    DropdownButtonFormField<String>(
                      value: _rubro,
                      decoration: const InputDecoration(labelText: 'Rubro Comercial / Industrial', border: OutlineInputBorder()),
                      items: ['Gastronómico', 'Comercial', 'Industrial', 'Supermercado', 'Hotelero', 'Servicios', 'Otros']
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (val) => setState(() => _rubro = val!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _categoriaGenerador,
                      decoration: const InputDecoration(labelText: 'Categoría de Generador', border: OutlineInputBorder()),
                      items: ['Pequeño Generador', 'Mediano Generador', 'Gran Generador (GIRSU)']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setState(() => _categoriaGenerador = val!),
                    ),
                  ] else ...[
                    TextField(
                      controller: _matriculaInaesController,
                      decoration: const InputDecoration(labelText: 'Matrícula INAES / Registro Oficial', border: OutlineInputBorder(), prefixIcon: Icon(Icons.verified)),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _tipoVehiculo,
                      decoration: const InputDecoration(labelText: 'Tipo de Vehículo Logístico', border: OutlineInputBorder()),
                      items: ['Camión Mediano/Grande', 'Camioneta / Furgón', 'Motocarga Trikar', 'Zorra Manual / Tracción Humana']
                          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (val) => setState(() => _tipoVehiculo = val!),
                    ),
                  ],
                ],
                if (_esLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => mostrarDialogoRecuperarPassword(context),
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _cargando ? null : _autenticar,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(50)),
                  child: _cargando ? const CircularProgressIndicator(color: Colors.white) : Text(_esLogin ? 'Iniciar Sesión' : 'Registrarse', style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
                TextButton(
                  onPressed: () => setState(() => _esLogin = !_esLogin),
                  child: Text(_esLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia Sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigationGenerador extends StatefulWidget {
  const MainNavigationGenerador({super.key});

  @override
  State<MainNavigationGenerador> createState() => _MainNavigationGeneradorState();
}

class _MainNavigationGeneradorState extends State<MainNavigationGenerador> {
  int _tabActual = 0;

  final List<Widget> _pantallas = const [
    PublicarResiduoScreen(),
    HistorialImpactoScreen(),
    PerfilUsuarioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pantallas[_tabActual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabActual,
        onTap: (index) => setState(() => _tabActual = index),
        selectedItemColor: Colors.green.shade800,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Clasificar'),
          BottomNavigationBarItem(icon: Icon(Icons.eco), label: 'Mi Impacto'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class MainNavigationRecuperador extends StatefulWidget {
  const MainNavigationRecuperador({super.key});

  @override
  State<MainNavigationRecuperador> createState() => _MainNavigationRecuperadorState();
}

class _MainNavigationRecuperadorState extends State<MainNavigationRecuperador> {
  int _tabActual = 0;

  final List<Widget> _pantallas = const [
    MarketplaceRecolectorScreen(),
    PerfilUsuarioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pantallas[_tabActual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabActual,
        onTap: (index) => setState(() => _tabActual = index),
        selectedItemColor: Colors.green.shade800,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa B2B'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class PublicarResiduoScreen extends StatefulWidget {
  const PublicarResiduoScreen({super.key});

  @override
  State<PublicarResiduoScreen> createState() => _PublicarResiduoScreenState();
}

class _PublicarResiduoScreenState extends State<PublicarResiduoScreen> {
  final ImagePicker _picker = ImagePicker();
  final GeminiService _geminiService = GeminiService();

  bool _cargando = false;
  bool _guardando = false;

  // Controllers para edición manual (Human-in-the-Loop)
  final _materialController = TextEditingController();
  final _subtipoController = TextEditingController();
  final _pesoController = TextEditingController();
  final _bultosController = TextEditingController(text: '1');
  final _direccionController = TextEditingController();
  final _instruccionesController = TextEditingController();
  String _condicionMaterial = 'Limpio y Seco';
  String _contenedorDestino = 'Contenedor Verde (Reciclables)';
  String _frecuenciaRetiro = 'Única vez';

  ResiduoModel? _datosOriginalesGemini;

  @override
  void initState() {
    super.initState();
    _cargarDireccionPerfil();
  }

  Future<void> _cargarDireccionPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (doc.exists && mounted) {
        final dir = doc.data()?['direccion_acopio'] ?? '';
        if (dir.isNotEmpty && _direccionController.text.isEmpty) {
          _direccionController.text = dir;
        }
      }
    }
  }

  Future<Position?> _obtenerUbicacionActual() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, activa el GPS / Ubicación.')),
        );
      }
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado.')),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso bloqueado. Habilita la ubicación para la app.')),
        );
      }
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener la ubicación: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _seleccionarImagen(ImageSource origen) async {
    try {
      final XFile? foto = await _picker.pickImage(source: origen);
      if (foto != null) {
        if (!mounted) return;
        setState(() => _cargando = true);

        final resultado = await _geminiService.analizarFotoResiduo(foto);

        if (!mounted) return;

        if (resultado != null) {
          setState(() {
            _datosOriginalesGemini = resultado;
            _materialController.text = resultado.materialPrincipal;
            _subtipoController.text = resultado.subtipoEspecifico;
            _pesoController.text = resultado.pesoEstimadoKg.toString();
            _condicionMaterial = resultado.condicionMaterial;
            _contenedorDestino = resultado.contenedorDestino;
            _instruccionesController.text = resultado.instruccionesPreparacion;
            _cargando = false;
          });
        } else {
          setState(() => _cargando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo analizar la imagen. Intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar la imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _guardarEnFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (_datosOriginalesGemini == null || user == null) return;

    final pesoIngresado = double.tryParse(_pesoController.text.trim()) ?? 0.0;
    final bultosIngresados = int.tryParse(_bultosController.text.trim()) ?? 1;

    if (pesoIngresado <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un peso válido mayor a 0 kg.')),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final position = await _obtenerUbicacionActual();

      if (!mounted) return;

      if (position == null) {
        setState(() => _guardando = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();

      if (!mounted) return;

      final userData = userDoc.data() ?? {};
      final orgName = userData['nombre_organizacion'] ?? user.email;
      final whatsapp = userData['telefono_whatsapp'] ?? '';
      final rubro = userData['rubro'] ?? 'Comercial';

      double co2NetoEvitado = CalculadoraImpactoACV.calcularCo2Neto(
        material: _materialController.text.trim(),
        pesoKg: pesoIngresado,
        distanciaKm: 12.0,
      );

      int ecopuntosACV = CalculadoraImpactoACV.calcularEcoPuntos(co2NetoEvitado);

      await FirebaseFirestore.instance.collection('residuos').add({
        'user_id': user.uid,
        'creador_nombre': orgName,
        'telefono_whatsapp': whatsapp,
        'rubro': rubro,
        'material_principal': _materialController.text.trim(),
        'subtipo_especifico': _subtipoController.text.trim(),
        'condicion_material': _condicionMaterial,
        'peso_estimado_kg': pesoIngresado,
        'cantidad_bultos': bultosIngresados,
        'direccion_exacta_acopio': _direccionController.text.trim(),
        'frecuencia_retiro_sugerida': _frecuenciaRetiro,
        'co2_evitado_estimado_kg': double.parse(co2NetoEvitado.toStringAsFixed(2)),
        'ecopuntos_estimados': ecopuntosACV,
        'instrucciones_preparacion': _instruccionesController.text.trim(),
        'contenedor_destino': _contenedorDestino,
        'estado': 'En Acopio',
        'latitud': position.latitude,
        'longitud': position.longitude,
        'fecha_creacion': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Declaración registrada exitosamente!'), backgroundColor: Colors.green),
        );
        setState(() {
          _datosOriginalesGemini = null;
          _materialController.clear();
          _subtipoController.clear();
          _pesoController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double pesoPreview = double.tryParse(_pesoController.text.trim()) ?? 0.0;
    double co2Preview = CalculadoraImpactoACV.calcularCo2Neto(
      material: _materialController.text.isEmpty ? 'Cartón' : _materialController.text,
      pesoKg: pesoPreview,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('NexoVerde - Clasificador ACV'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Declaración Previa de Residuo B2B',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sube una foto para clasificar con IA y ajusta manualmente los datos si lo requieres (Human-in-the-Loop).',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cargando ? null : () => _seleccionarImagen(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Cámara'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade100,
                      foregroundColor: Colors.green.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cargando ? null : () => _seleccionarImagen(ImageSource.gallery),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir Foto'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade800,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_cargando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Gemini IA analizando material y subtipo...'),
                    ],
                  ),
                ),
              ),
            if (_datosOriginalesGemini != null) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note, color: Colors.green.shade800),
                          const SizedBox(width: 8),
                          Text('Edición Manual de Declaración', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _materialController,
                        decoration: const InputDecoration(labelText: 'Material Principal (Predicho por IA)', border: OutlineInputBorder()),
                        onChanged: (val) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _subtipoController,
                        decoration: const InputDecoration(labelText: 'Subtipo Especificación', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pesoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Peso Total (Kg)', border: OutlineInputBorder()),
                              onChanged: (val) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _bultosController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Bultos / Fardos', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _direccionController,
                        decoration: const InputDecoration(labelText: 'Dirección Exacta de Acopio en Corrientes', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_drop)),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _frecuenciaRetiro,
                        decoration: const InputDecoration(labelText: 'Frecuencia de Retiro Sugerida', border: OutlineInputBorder()),
                        items: ['Única vez', 'Semanal', 'Quincenal', 'Mensual']
                            .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                            .toList(),
                        onChanged: (val) => setState(() => _frecuenciaRetiro = val!),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Impacto ACV Recalculado:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('${co2Preview.toStringAsFixed(2)} kg CO₂e', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarEnFirestore,
                icon: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: Text(_guardando ? 'Obteniendo GPS y Guardando...' : 'Publicar con Geolocalización'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HistorialImpactoScreen extends StatelessWidget {
  const HistorialImpactoScreen({super.key});

  Color _obtenerColorContenedor(String contenedor) {
    final text = contenedor.toLowerCase();
    if (text.contains('amarillo') || text.contains('plástico') || text.contains('plastico')) return Colors.amber.shade100;
    if (text.contains('azul') || text.contains('papel') || text.contains('cartón') || text.contains('carton')) return Colors.blue.shade100;
    if (text.contains('verde') || text.contains('vidrio')) return Colors.green.shade100;
    return Colors.grey.shade200;
  }

  void _mostrarDetallesYAcciones(BuildContext context, QueryDocumentSnapshot doc) {
    final item = doc.data() as Map<String, dynamic>;
    String estadoActual = item['estado'] ?? 'En Acopio';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item['material_principal'] ?? 'Residuo',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Eliminar registro',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Eliminar registro'),
                                content: const Text('¿Estás seguro de que deseas eliminar este residuo?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await FirebaseFirestore.instance.collection('residuos').doc(doc.id).delete();
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro eliminado correctamente.')));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Subtipo: ${item['subtipo_especifico'] ?? 'No especificado'}'),
                    Text('Condición: ${item['condicion_material'] ?? 'No especificada'}'),
                    Text('Peso estimado: ${item['peso_estimado_kg'] ?? 0} kg | Bultos: ${item['cantidad_bultos'] ?? 1}'),
                    Text('Frecuencia: ${item['frecuencia_retiro_sugerida'] ?? 'Única vez'}'),
                    Text('Dirección Acopio: ${item['direccion_exacta_acopio'] ?? 'Corrientes Capital'}'),
                    Text('CO₂ Evitado (Neto ACV): ${item['co2_evitado_estimado_kg'] ?? 0} kg'),
                    const SizedBox(height: 12),
                    const Text('Instrucciones de Preparación:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text(item['instrucciones_preparacion'] ?? 'Sin instrucciones registradas.', style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Cambiar Estado:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['En Acopio', 'En Tránsito', 'Reciclado'].map((estado) {
                        final esSeleccionado = estadoActual == estado;
                        return ChoiceChip(
                          label: Text(estado),
                          selected: esSeleccionado,
                          selectedColor: Colors.green.shade200,
                          onSelected: (selected) async {
                            if (selected) {
                              setStateModal(() => estadoActual = estado);
                              await FirebaseFirestore.instance.collection('residuos').doc(doc.id).update({'estado': estado});
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generarPDF(BuildContext context, List<QueryDocumentSnapshot> docs, String userEmail, String uid) async {
    final pdf = pw.Document();
    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final profileData = userDoc.data() ?? {};
    final nombreOrg = profileData['nombre_organizacion'] ?? userEmail;
    final direccion = profileData['direccion_acopio'] ?? 'Corrientes Capital';

    double totalCO2 = 0.0;
    int totalEcopuntos = 0;
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      totalCO2 += ((data['co2_evitado_estimado_kg'] ?? 0.0) as num).toDouble();
      totalEcopuntos += ((data['ecopuntos_estimados'] ?? 0) as num).toInt();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('NexoVerde - Certificado de Impacto Ambiental ACV', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                pw.Text(DateTime.now().toString().split(' ')[0], style: const pw.TextStyle(color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Organización / Generador: $nombreOrg', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('Ubicación: $direccion (Corrientes)', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          pw.Text('Operador / Recuperador: Coop. de Trabajo Ñandereko Recrea Ltda.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 15),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text('CO2 Evitado Neto (ACV)', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('${totalCO2.toStringAsFixed(2)} kg', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('EcoPuntos Acumulados', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('$totalEcopuntos pts', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Detalle de Residuos Gestionados:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: ['Material', 'Subtipo', 'Peso (kg)', 'CO2 Neto Evitado', 'Estado'],
            data: docs.map((doc) {
              final item = doc.data() as Map<String, dynamic>;
              return [
                item['material_principal'] ?? 'Residuo',
                item['subtipo_especifico'] ?? '-',
                '${item['peso_estimado_kg'] ?? 0}',
                '${item['co2_evitado_estimado_kg'] ?? 0} kg',
                item['estado'] ?? 'En Acopio',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
            cellAlignment: pw.Alignment.centerLeft,
            cellHeight: 24,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Certificado_NexoVerde_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Impacto Ambiental (ACV)'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Dashboard ESG',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EsgDashboardScreen()),
              );
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('residuos').where('user_id', isEqualTo: user?.uid ?? '').snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              return IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Exportar Certificado PDF',
                onPressed: docs.isEmpty ? null : () => _generarPDF(context, docs, user?.email ?? 'Usuario', user?.uid ?? ''),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('residuos').where('user_id', isEqualTo: user?.uid ?? '').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('Aún no tienes residuos creados.'));

          double totalCO2 = 0.0;
          int totalEcopuntos = 0;
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalCO2 += ((data['co2_evitado_estimado_kg'] ?? 0.0) as num).toDouble();
            totalEcopuntos += ((data['ecopuntos_estimados'] ?? 0) as num).toInt();
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.green.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _TarjetaMetrica(titulo: 'CO₂ Net. Evitado', valor: '${totalCO2.toStringAsFixed(2)} kg', icono: Icons.cloud_done, color: Colors.green.shade800),
                    _TarjetaMetrica(titulo: 'EcoPuntos ACV', valor: '$totalEcopuntos pts', icono: Icons.stars, color: Colors.orange.shade800),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.all(12.0),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final item = doc.data() as Map<String, dynamic>;
                    final colorContenedor = _obtenerColorContenedor(item['contenedor_destino'] ?? '');

                    return Card(
                      color: colorContenedor,
                      margin: const EdgeInsets.only(bottom: 12.0),
                      child: ListTile(
                        onTap: () => _mostrarDetallesYAcciones(context, doc),
                        leading: CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.recycling, color: Colors.green.shade700)),
                        title: Text(item['material_principal'] ?? 'Residuo', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Estado: ${item['estado'] ?? 'En Acopio'} | ${item['peso_estimado_kg']} kg\n(Toca para ver detalles)'),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _TarjetaMetrica({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 28),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class MarketplaceRecolectorScreen extends StatefulWidget {
  const MarketplaceRecolectorScreen({super.key});

  @override
  State<MarketplaceRecolectorScreen> createState() => _MarketplaceRecolectorScreenState();
}

class _MarketplaceRecolectorScreenState extends State<MarketplaceRecolectorScreen> {
  bool _verMapa = true;

  // Ubicaciones fijas de Corrientes (Sustituido '_coopÑandereko' por '_coopNandereko' para estándar ASCII)
  final LatLng _coopNandereko = const LatLng(-27.4682, -58.8320);
  final List<Map<String, dynamic>> _ecopuntosMunicipales = const [
    {'nombre': 'Ecopunto Plaza Libertad', 'pos': LatLng(-27.4720, -58.8285)},
    {'nombre': 'Ecopunto Plaza Torrent', 'pos': LatLng(-27.4678, -58.8350)},
    {'nombre': 'Ecopunto Parque Mitre', 'pos': LatLng(-27.4580, -58.8310)},
    {'nombre': 'Ecopunto Plaza Vera', 'pos': LatLng(-27.4665, -58.8368)},
    {'nombre': 'Ecopunto Cambá Cuá', 'pos': LatLng(-27.4635, -58.8412)},
  ];

  void _mostrarNotificacionAlerta(int acopiosCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.amber),
            SizedBox(width: 8),
            Text('Alertas Logísticas'),
          ],
        ),
        content: Text(
          acopiosCount > 0
              ? '¡Atención Recuperadores! Hay $acopiosCount punto(s) de acopio pendiente(s) de retiro en Corrientes Capital.'
              : 'No hay acopios pendientes en este momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa B2B - Corrientes'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('residuos').where('estado', isEqualTo: 'En Acopio').snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    tooltip: 'Notificaciones y Alertas',
                    onPressed: () => _mostrarNotificacionAlerta(count),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$count',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(_verMapa ? Icons.list : Icons.map),
            tooltip: _verMapa ? 'Ver en Lista' : 'Ver en Mapa',
            onPressed: () => setState(() => _verMapa = !_verMapa),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('residuos').where('estado', isEqualTo: 'En Acopio').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];

          if (!_verMapa) {
            if (docs.isEmpty) return const Center(child: Text('No hay acopios disponibles en Corrientes Capital.'));
            return ListView.builder(
              itemCount: docs.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final item = docs[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text('${item['material_principal']} - ${item['subtipo_especifico'] ?? ""}'),
                    subtitle: Text('Origen: ${item['creador_nombre']}\nPeso: ${item['peso_estimado_kg']} kg | Bultos: ${item['cantidad_bultos'] ?? 1}\nDirección: ${item['direccion_exacta_acopio'] ?? "Corrientes"}'),
                    trailing: const Icon(Icons.location_on, color: Colors.red),
                  ),
                );
              },
            );
          }

          List<Marker> markers = [];

          // 1. Marcador Permanente: Coop. Ñandereko Recrea Ltda.
          markers.add(
            Marker(
              point: _coopNandereko,
              width: 45,
              height: 45,
              child: GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Coop. de Trabajo Ñandereko Recrea Ltda.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                          SizedBox(height: 8),
                          Text('Centro de Acopio Central y Clasificación'),
                          Text('Ubicación: Corrientes Capital'),
                        ],
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.store, color: Colors.blue, size: 40),
              ),
            ),
          );

          // 2. Marcadores Permanentes: Ecopuntos Municipales
          for (var eco in _ecopuntosMunicipales) {
            markers.add(
              Marker(
                point: eco['pos'] as LatLng,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(eco['nombre'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                            const SizedBox(height: 8),
                            const Text('Punto Verde Municipal de Recepción Diferenciada'),
                            const Text('Público en General y Separación en Origen'),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Icon(Icons.eco, color: Colors.teal, size: 36),
                ),
              ),
            );
          }

          // 3. Marcadores Dinámicos: Residuos Generados por Empresas
          for (var doc in docs) {
            final item = doc.data() as Map<String, dynamic>;
            final lat = (item['latitud'] ?? -27.4698) as double;
            final lng = (item['longitud'] ?? -58.8306) as double;

            markers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 45,
                height: 45,
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['material_principal'] ?? 'Residuo', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text('Generador: ${item['creador_nombre']} (${item['rubro'] ?? "Comercial"})'),
                            Text('Peso: ${item['peso_estimado_kg']} kg | Bultos: ${item['cantidad_bultos'] ?? 1}'),
                            Text('Frecuencia Sugerida: ${item['frecuencia_retiro_sugerida'] ?? "Única vez"}'),
                            Text('Dirección: ${item['direccion_exacta_acopio'] ?? "Sin especificar"}'),
                            if ((item['telefono_whatsapp'] ?? '').toString().isNotEmpty)
                              Text('WhatsApp: ${item['telefono_whatsapp']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                              icon: const Icon(Icons.local_shipping),
                              label: const Text('Aceptar Retiro / Iniciar Logística'),
                              onPressed: () async {
                                Navigator.pop(context);
                                await FirebaseFirestore.instance.collection('residuos').doc(doc.id).update({'estado': 'En Tránsito'});
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Icon(Icons.location_on, color: Colors.red, size: 42),
                ),
              ),
            );
          }

          return FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-27.4682, -58.8320),
              initialZoom: 13.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nexoverde.app',
              ),
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
    );
  }
}

class PerfilUsuarioScreen extends StatefulWidget {
  const PerfilUsuarioScreen({super.key});

  @override
  State<PerfilUsuarioScreen> createState() => _PerfilUsuarioScreenState();
}

class _PerfilUsuarioScreenState extends State<PerfilUsuarioScreen> {
  final _orgController = TextEditingController();
  final _cuitController = TextEditingController();
  final _direccionController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _matriculaInaesController = TextEditingController();
  String _rubro = 'Gastronómico';
  String _categoriaGenerador = 'Mediano Generador';
  String _tipoVehiculo = 'Camioneta / Furgón';
  String _rol = 'generador';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _orgController.text = data['nombre_organizacion'] ?? '';
        _cuitController.text = data['cuit'] ?? '';
        _direccionController.text = data['direccion_acopio'] ?? '';
        _whatsappController.text = data['telefono_whatsapp'] ?? '';
        _matriculaInaesController.text = data['matricula_inaes'] ?? '';
        setState(() {
          _rol = data['rol'] ?? 'generador';
          _rubro = data['rubro'] ?? 'Gastronómico';
          _categoriaGenerador = data['categoria_generador'] ?? 'Mediano Generador';
          _tipoVehiculo = data['tipo_vehiculo'] ?? 'Camioneta / Furgón';
        });
      }
    }
  }

  Future<void> _guardarPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _guardando = true);
    try {
      Map<String, dynamic> datos = {
        'nombre_organizacion': _orgController.text.trim(),
        'cuit': _cuitController.text.trim(),
        'direccion_acopio': _direccionController.text.trim(),
        'telefono_whatsapp': _whatsappController.text.trim(),
        'email': user.email,
      };

      if (_rol == 'generador') {
        datos['rubro'] = _rubro;
        datos['categoria_generador'] = _categoriaGenerador;
      } else {
        datos['matricula_inaes'] = _matriculaInaesController.text.trim();
        datos['tipo_vehiculo'] = _tipoVehiculo;
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(datos, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado correctamente.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil Institucional'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.green.shade100,
                child: Icon(
                  _rol == 'recuperador' ? Icons.local_shipping : Icons.business,
                  size: 40,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Chip(
                  label: Text(
                    _rol == 'recuperador' ? 'Rol: Cooperativa / Recuperador' : 'Rol: Empresa Generadora',
                    style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.green.shade100,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  user?.email ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _orgController,
                decoration: const InputDecoration(labelText: 'Nombre de la Organización', border: OutlineInputBorder(), prefixIcon: Icon(Icons.domain)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cuitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CUIT / Identificación Fiscal', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono WhatsApp', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _direccionController,
                decoration: const InputDecoration(labelText: 'Dirección Base en Corrientes', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_city)),
              ),
              const SizedBox(height: 12),
              if (_rol == 'generador') ...[
                DropdownButtonFormField<String>(
                  value: _rubro,
                  decoration: const InputDecoration(labelText: 'Rubro Comercial / Industrial', border: OutlineInputBorder()),
                  items: ['Gastronómico', 'Comercial', 'Industrial', 'Supermercado', 'Hotelero', 'Servicios', 'Otros']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) => setState(() => _rubro = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoriaGenerador,
                  decoration: const InputDecoration(labelText: 'Categoría de Generador', border: OutlineInputBorder()),
                  items: ['Pequeño Generador', 'Mediano Generador', 'Gran Generador (GIRSU)']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => _categoriaGenerador = val!),
                ),
              ] else ...[
                TextField(
                  controller: _matriculaInaesController,
                  decoration: const InputDecoration(labelText: 'Matrícula INAES', border: OutlineInputBorder(), prefixIcon: Icon(Icons.verified)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _tipoVehiculo,
                  decoration: const InputDecoration(labelText: 'Tipo de Vehículo Logístico', border: OutlineInputBorder()),
                  items: ['Camión Mediano/Grande', 'Camioneta / Furgón', 'Motocarga Trikar', 'Zorra Manual / Tracción Humana']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (val) => setState(() => _tipoVehiculo = val!),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarPerfil,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar Cambios'),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar Sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EsgDashboardScreen extends StatelessWidget {
  const EsgDashboardScreen({super.key});

  Future<void> _exportarPdfReporteESG({
    required BuildContext context,
    required String userEmail,
    required String uid,
    required double totalCO2,
    required double totalPesoKg,
    required int totalEcopuntos,
    required String tasaCircularidad,
    required Map<String, double> pesoPorMaterial,
  }) async {
    final pdf = pw.Document();
    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final profileData = userDoc.data() ?? {};
    final nombreOrg = profileData['nombre_organizacion'] ?? userEmail;
    final cuit = profileData['cuit'] ?? 'Sin CUIT';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('NexoVerde - Reporte de Sustentabilidad ESG (ACV)',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                pw.Text(DateTime.now().toString().split(' ')[0], style: const pw.TextStyle(color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Empresa / Organización: $nombreOrg', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('CUIT: $cuit | Usuario: $userEmail', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          pw.Text('Operador Logístico: Cooperativa de Trabajo Ñandereko Recrea Ltda.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
          pw.SizedBox(height: 15),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text('CO2 Neto Evitado', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('${totalCO2.toStringAsFixed(1)} kg', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('Material Desviado', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('${totalPesoKg.toStringAsFixed(1)} kg', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('Circularidad', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('$tasaCircularidad%', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('EcoPuntos', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('$totalEcopuntos pts', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Desglose por Tipo de Material:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: ['Material', 'Peso Total (kg)', 'Porcentaje del Total'],
            data: pesoPorMaterial.entries.map((e) {
              final pct = totalPesoKg > 0 ? (e.value / totalPesoKg * 100).toStringAsFixed(1) : '0.0';
              return [e.key, '${e.value.toStringAsFixed(1)} kg', '$pct %'];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
            cellAlignment: pw.Alignment.centerLeft,
            cellHeight: 22,
          ),
          pw.SizedBox(height: 20),
          pw.Text('Equivalencias de Impacto Ambiental Real:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Bullet(text: 'Absorción equivalente a ${(totalCO2 / 20.0).toStringAsFixed(1)} árboles en un año.'),
          pw.Bullet(text: 'Equivalente a ${(totalCO2 * 4.1).toStringAsFixed(0)} km no recorridos por vehículos a combustión.'),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Reporte_ESG_NexoVerde_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard ESG / IPCC Corrientes'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('residuos')
            .where('user_id', isEqualTo: user?.uid ?? '')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aún no hay datos registrados para generar métricas ESG.'),
            );
          }

          double totalCO2 = 0;
          double totalPesoKg = 0;
          int totalEcopuntos = 0;
          int completados = 0;
          Map<String, double> pesoPorMaterial = {};

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final co2 = ((data['co2_evitado_estimado_kg'] ?? 0) as num).toDouble();
            final peso = ((data['peso_estimado_kg'] ?? 0) as num).toDouble();
            final pts = ((data['ecopuntos_estimados'] ?? 0) as num).toInt();
            final mat = (data['material_principal'] ?? 'Otros').toString();
            final estado = (data['estado'] ?? '').toString();

            totalCO2 += co2;
            totalPesoKg += peso;
            totalEcopuntos += pts;
            pesoPorMaterial[mat] = (pesoPorMaterial[mat] ?? 0) + peso;

            if (estado == 'Reciclado') completados++;
          }

          final arbolesEquivalentes = (totalCO2 / 20.0).toStringAsFixed(1);
          final kmAutosEvitados = (totalCO2 * 4.1).toStringAsFixed(0);
          final tasaCircularidad = ((completados / docs.length) * 100).toStringAsFixed(1);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reporte de Impacto Ambiental ACV',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Generador: ${user?.email ?? "Empresa"}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Text(
                        'Recuperador Asociado: Coop. Ñandereko Recrea Ltda.',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _exportarPdfReporteESG(
                    context: context,
                    userEmail: user?.email ?? 'Usuario',
                    uid: user?.uid ?? '',
                    totalCO2: totalCO2,
                    totalPesoKg: totalPesoKg,
                    totalEcopuntos: totalEcopuntos,
                    tasaCircularidad: tasaCircularidad,
                    pesoPorMaterial: pesoPorMaterial,
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exportar Reporte ESG en PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _TarjeKpi(
                      titulo: 'CO₂ Neto Evitado',
                      valor: '${totalCO2.toStringAsFixed(1)} kg',
                      subtexto: 'Cálculo ACV/IPCC',
                      color: Colors.green.shade700,
                      icono: Icons.eco,
                    ),
                    _TarjeKpi(
                      titulo: 'Desviados de Basural',
                      valor: '${totalPesoKg.toStringAsFixed(1)} kg',
                      subtexto: 'Total recuperado',
                      color: Colors.blue.shade700,
                      icono: Icons.scale,
                    ),
                    _TarjeKpi(
                      titulo: 'Tasa Circularidad',
                      valor: '$tasaCircularidad%',
                      subtexto: 'Material procesado',
                      color: Colors.teal.shade700,
                      icono: Icons.loop,
                    ),
                    _TarjeKpi(
                      titulo: 'EcoPuntos ACV',
                      valor: '$totalEcopuntos',
                      subtexto: 'Créditos acumulados',
                      color: Colors.orange.shade800,
                      icono: Icons.military_tech,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Equivalencias de Impacto Real', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.park, color: Colors.white)),
                          title: Text('$arbolesEquivalentes Árboles'),
                          subtitle: const Text('Equivalencia en absorción anual de CO₂'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_car, color: Colors.white)),
                          title: Text('$kmAutosEvitados km'),
                          subtitle: const Text('Kilómetros no recorridos por vehículos a combustión'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Composición de Residuos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: pesoPorMaterial.entries.map((entry) {
                        final porcentaje = totalPesoKg > 0 ? (entry.value / totalPesoKg) : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('${entry.value.toStringAsFixed(1)} kg (${(porcentaje * 100).toStringAsFixed(0)}%)'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: porcentaje,
                                backgroundColor: Colors.grey.shade200,
                                color: Colors.green.shade600,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjeKpi extends StatelessWidget {
  final String titulo;
  final String valor;
  final String subtexto;
  final Color color;
  final IconData icono;

  const _TarjeKpi({
    required this.titulo,
    required this.valor,
    required this.subtexto,
    required this.color,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
              Icon(icono, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(subtexto, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }
}