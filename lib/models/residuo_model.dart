class ResiduoModel {
  final String id;
  final String materialPrincipal;
  final String subtipoEspecifico;
  final String condicionMaterial;
  int cantidadBultos;
  double pesoEstimadoKg;
  double? pesoVerificadoKg; // Exclusivo de la cooperativa
  final String instruccionesPreparacion;
  final String contenedorDestino;
  String estado; // 'DECLARADO', 'EN_TRANSITO', 'RECIBIDO_EN_COOPERATIVA'
  double co2EvitadoKg;
  int ecopuntos;

  ResiduoModel({
    required this.id,
    required this.materialPrincipal,
    required this.subtipoEspecifico,
    required this.condicionMaterial,
    this.cantidadBultos = 1,
    required this.pesoEstimadoKg,
    this.pesoVerificadoKg,
    required this.instruccionesPreparacion,
    required this.contenedorDestino,
    this.estado = 'DECLARADO',
    this.co2EvitadoKg = 0.0,
    this.ecopuntos = 0,
  });

  factory ResiduoModel.fromJson(Map<String, dynamic> json) {
    return ResiduoModel(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      materialPrincipal: json['material_principal'] ?? json['materialPrincipal'] ?? 'Desconocido',
      subtipoEspecifico: json['subtipo_especifico'] ?? json['subtipoEspecifico'] ?? 'General',
      condicionMaterial: json['condicion_material'] ?? json['condicionMaterial'] ?? 'A granel',
      cantidadBultos: json['cantidad_bultos'] ?? json['cantidadBultos'] ?? 1,
      pesoEstimadoKg: (json['peso_estimado_kg'] ?? json['pesoEstimadoKg'] ?? 0.0).toDouble(),
      pesoVerificadoKg: json['peso_verificado_kg'] != null ? (json['peso_verificado_kg'] as num).toDouble() : null,
      instruccionesPreparacion: json['instrucciones_preparacion'] ?? json['instruccionesPreparacion'] ?? '',
      contenedorDestino: json['contenedor_destino'] ?? json['contenedorDestino'] ?? 'Gris',
      estado: json['estado'] ?? 'DECLARADO',
      co2EvitadoKg: (json['co2_evitado_kg'] ?? json['co2EvitadoKg'] ?? 0.0).toDouble(),
      ecopuntos: json['ecopuntos'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'materialPrincipal': materialPrincipal,
      'subtipoEspecifico': subtipoEspecifico,
      'condicionMaterial': condicionMaterial,
      'cantidadBultos': cantidadBultos,
      'pesoEstimadoKg': pesoEstimadoKg,
      'pesoVerificadoKg': pesoVerificadoKg,
      'instruccionesPreparacion': instruccionesPreparacion,
      'contenedorDestino': contenedorDestino,
      'estado': estado,
      'co2EvitadoKg': co2EvitadoKg,
      'ecopuntos': ecopuntos,
    };
  }

  // Método para actualizar impacto cuando la cooperativa pesa el residuo
  void calcularImpactoFinal(double factorCo2PorKg, int factorEcopuntosPorKg) {
    final pesoFinal = pesoVerificadoKg ?? pesoEstimadoKg;
    co2EvitadoKg = pesoFinal * factorCo2PorKg;
    ecopuntos = (pesoFinal * factorEcopuntosPorKg).round();
    estado = 'RECIBIDO_EN_COOPERATIVA';
  }
}