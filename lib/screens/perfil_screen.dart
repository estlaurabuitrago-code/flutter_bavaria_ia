import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PerfilScreen extends StatefulWidget {
  final String usuarioId;
  final String usuarioNombre;

  const PerfilScreen({
    super.key,
    required this.usuarioId,
    required this.usuarioNombre,
  });

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  static const _kPurple = Color(0xFF663399);
  static const _kLightPurple = Color(0xFFF2EBFA);

  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _maquinasEscaneadas = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMaquinas();
  }

  Future<void> _loadMaquinas() async {
    try {
      final data = await _supabase
          .from('reporte')
          .select('maquina_id, maquina(nombre), cantidad_rayones, fecha_hora')
          .eq('usuario_id', int.parse(widget.usuarioId))
          .order('fecha_hora', ascending: false);

      final list = List<Map<String, dynamic>>.from(data as List);

      // Agrupar por máquina: última fecha y total de reportes
      final Map<int, Map<String, dynamic>> grouped = {};
      for (final r in list) {
        final mid = r['maquina_id'] as int;
        if (!grouped.containsKey(mid)) {
          grouped[mid] = {
            'nombre': (r['maquina'] as Map)['nombre'],
            'ultima_fecha': r['fecha_hora'],
            'total_reportes': 1,
          };
        } else {
          grouped[mid]!['total_reportes'] =
              (grouped[mid]!['total_reportes'] as int) + 1;
        }
      }

      setState(() {
        _maquinasEscaneadas = grouped.values.toList();
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
        title: const Text(
          'Perfil',
          style: TextStyle(color: _kPurple, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: _kPurple),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: _kLightPurple,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: _kPurple,
                  child: Icon(Icons.person, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.usuarioNombre,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _kPurple,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Máquinas escaneadas',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
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
    if (_maquinasEscaneadas.isEmpty) {
      return const Center(
        child: Text(
          'Aún no has guardado reportes',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _maquinasEscaneadas.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _maquinasEscaneadas[i];
        final fecha = DateTime.tryParse(m['ultima_fecha'] as String? ?? '');
        final fechaStr = fecha != null
            ? '${fecha.day}/${fecha.month}/${fecha.year}'
            : '-';
        return ListTile(
          leading: const Icon(Icons.forklift, color: _kPurple),
          title: Text(
            'Montacargas ${m['nombre']}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text('Último escaneo: $fechaStr'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kLightPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${m['total_reportes']} reporte${m['total_reportes'] == 1 ? '' : 's'}',
              style: const TextStyle(
                color: _kPurple,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }
}
