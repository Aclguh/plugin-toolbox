import 'package:flutter/material.dart';

class AppColorSchemes {
  AppColorSchemes._();

  static const Color seedColor = Color(0xFF006B5E);

  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
}
