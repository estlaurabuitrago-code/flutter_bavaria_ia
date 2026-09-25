import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/password_hasher.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _supabase = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Map<String, dynamic>> _maquinas = [];
  Map<String, dynamic>? _selectedMaquina;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMaquinas();
  }

  Future<void> _loadMaquinas() async {
    setState(() {
      _loadError = null;
    });
    try {
      final data = await _supabase.from('maquina').select().order('nombre');
      final list = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _maquinas = list;
        _loading = false;
        if (list.isEmpty) _loadError = 'La tabla maquina está vacía';
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _iniciar() async {
    if (_selectedMaquina == null) {
      setState(() => _error = 'Selecciona una máquina');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Ingresa tu usuario y contraseña');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final found = await _supabase
          .from('usuario')
          .select()
          .ilike('email', email)
          .maybeSingle();

      if (found == null) {
        setState(() {
          _error = 'Usuario o contraseña incorrectos';
          _submitting = false;
        });
        return;
      }

      final usuario = Map<String, dynamic>.from(found as Map);
      final storedHash = usuario['password_hash'] as String?;
      final storedSalt = usuario['password_salt'] as String?;
      final valid =
          storedHash != null &&
          storedSalt != null &&
          PasswordHasher.verify(password, storedSalt, storedHash);

      if (!valid) {
        setState(() {
          _error = 'Usuario o contraseña incorrectos';
          _submitting = false;
        });
        return;
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            maquinaId: _selectedMaquina!['id'].toString(),
            maquinaNombre: _selectedMaquina!['nombre'] as String,
            usuarioId: usuario['id'].toString(),
            usuarioNombre: usuario['nombre'] as String,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Error al iniciar: $e';
        _submitting = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Logo Lift Scan — centrado, parte superior
            Positioned(
              top: MediaQuery.of(context).size.height * 0.04,
              left: 0,
              right: 0,
              child: Center(
                child: Image.asset(
                  'assets/images/logo_liftscan.jpg',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            // Logo Bavaria — esquina superior derecha
            Positioned(
              top: 0,
              right: 6,
              child: Image.asset(
                'assets/images/logo_bavaria.png',
                width: 90,
                height: 90,
                fit: BoxFit.contain,
              ),
            ),
            // Tarjeta de login
            Align(
              alignment: const Alignment(0, 0.3),
              child: FractionallySizedBox(
                widthFactor: 0.80,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Máquina',
                        style: TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _maquinas.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _loadError ??
                                      'No se pudieron cargar las máquinas',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _loading = true);
                                    _loadMaquinas();
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Reintentar'),
                                ),
                              ],
                            )
                          : DropdownButtonFormField<Map<String, dynamic>>(
                              initialValue: _selectedMaquina,
                              hint: const Text('Seleccionar máquina'),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: _maquinas
                                  .map(
                                    (m) =>
                                        DropdownMenuItem<Map<String, dynamic>>(
                                          value: m,
                                          child: Text(m['nombre'] as String),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedMaquina = v;
                                _error = null;
                              }),
                            ),
                      const SizedBox(height: 10),
                      const Text(
                        'Usuario (correo)',
                        style: TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Tu correo',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Contraseña',
                        style: TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Tu contraseña',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _iniciar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF663399),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Iniciar Escaneo',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(
                            context,
                            '/register',
                          ),
                          child: const Text(
                            '¿No tienes cuenta? Regístrate',
                            style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                            ),
                          ),
                        ),
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
}
