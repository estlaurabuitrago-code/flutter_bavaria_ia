import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://odvqbgxrykysmlxyeghk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9kdnFiZ3hyeWt5c21seHllZ2hrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk5NzY1MjcsImV4cCI6MjA5NTU1MjUyN30.FHxfiAQKhpF4Z-llbZQz0ZgFoEJsDxd1JUjGW9A9z14',
  );
  runApp(const BavariaIAApp());
}

class BavariaIAApp extends StatelessWidget {
  const BavariaIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bavaria IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF663399)),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
