import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrosScreen extends StatefulWidget {
  final String maquinaId;
  final String maquinaNombre;

  const RegistrosScreen({
    super.key,
    required this.maquinaId,
    required this.maquinaNombre,
  });

  @override
  State<RegistrosScreen> createState() => _RegistrosScreenState();
}

class _RegistrosScreenState extends State<RegistrosScreen> {
  static const _kPurple = Color(0xFF663399);
  static const _kLightPurple = Color(0xFFF2EBFA);

  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _reportes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReportes();
  }

  Future<void> _loadReportes() async {
    try {
      final data = await _supabase
          .from('reporte')
          .select('id, fecha_hora, cantidad_rayones, confianza, observaciones, foto_rayon_url, usuario(nombre)')
          .eq('maquina_id', int.parse(widget.maquinaId))
          .order('fecha_hora', ascending: false);

      setState(() {
        _reportes = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kLightPurple,
        foregroundColor: _kPurple,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Registros',
              style: TextStyle(
                color: _kPurple,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              'Montacargas ${widget.maquinaNombre}',
              style: const TextStyle(color: _kPurple, fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: _kPurple),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_reportes.isEmpty) {
      return const Center(
        child: Text(
          'No hay reportes para esta máquina',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reportes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _reportes[i];
        final fecha = DateTime.tryParse(r['fecha_hora'] as String? ?? '');
        final fechaStr = fecha != null
            ? '${fecha.day}/${fecha.month}/${fecha.year}  ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
            : '-';
        final opm = (r['usuario'] as Map?)?.containsKey('nombre') == true
            ? r['usuario']['nombre'] as String
            : 'Desconocido';
        final confianza = r['confianza'] != null
            ? '${((r['confianza'] as num) * 100).toStringAsFixed(0)}%'
            : '-';
        final rayones = r['cantidad_rayones'] as int? ?? 0;
        final obs = r['observaciones'] as String?;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kLightPurple,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fechaStr,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _kPurple,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: rayones > 0 ? Colors.red[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$rayones rayón${rayones == 1 ? '' : 'es'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: rayones > 0 ? Colors.red[800] : Colors.green[800],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(opm, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 16),
                  const Icon(Icons.analytics_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Confianza: $confianza',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              if (obs != null && obs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  obs,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
              if (r['foto_rayon_url'] != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    r['foto_rayon_url'] as String,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 60,
                      child: Center(
                        child: Text(
                          'Foto no disponible',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
