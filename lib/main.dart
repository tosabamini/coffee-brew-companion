import 'package:flutter/material.dart';
import 'features/scale/screens/main_screen.dart';

void main() {
  runApp(const CoffeeScaleApp());
}

class CoffeeScaleApp extends StatelessWidget {
  const CoffeeScaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coffee Scale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}