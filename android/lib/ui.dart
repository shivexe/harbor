import 'package:flutter/material.dart';

const canvas = Color(0xff242426);
const panel = Color(0xff1c1c1e);
const raised = Color(0xff303033);
const ink = Color(0xfff2f2f2);
const muted = Color(0xffb1b1b6);
const action = Color(0xff409cff);
const buttonFill = Color(0xff0068d9);
const hairline = Color(0xff48484a);

ThemeData harborTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: canvas,
  colorScheme: const ColorScheme.dark(
    primary: action,
    onPrimary: panel,
    surface: panel,
    onSurface: ink,
    error: Color(0xffffa8a8),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: panel,
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
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: hairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: hairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: action, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      backgroundColor: buttonFill,
      foregroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: hairline),
    ),
  ),
);
