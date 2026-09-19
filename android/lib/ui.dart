import 'package:flutter/material.dart';

const canvas = Color(0xff17191f);
const panel = Color(0xff1d2028);
const raised = Color(0xff272b35);
const ink = Color(0xfff1f2f6);
const muted = Color(0xffabb1c0);
const action = Color(0xffa8b8fa);
const hairline = Color(0xff363b47);

ThemeData harborTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: canvas,
  colorScheme: const ColorScheme.dark(
    primary: action,
    onPrimary: canvas,
    surface: panel,
    onSurface: ink,
    error: Color(0xffffa8a8),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'Roboto',
      color: ink,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: raised,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide.none,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      side: const BorderSide(color: hairline),
    ),
  ),
);
