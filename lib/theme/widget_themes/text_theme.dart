import 'package:flutter/material.dart';
import 'package:hologram_test/utils/app_export.dart';
import '../../utils/constants/colors.dart';

/// Custom Class for Light & Dark Text Themes
class AppTextTheme {
  AppTextTheme._(); // To avoid creating instances

  /// Customizable Light Text Theme
  static TextTheme lightTextTheme = TextTheme(
    headlineLarge: const TextStyle().copyWith(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.black,),
    headlineMedium: const TextStyle().copyWith(fontSize: 24, fontWeight: FontWeight.w400, color: AppColors.black),
    headlineSmall: const TextStyle().copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.black,),

    titleLarge: const TextStyle().copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.black,letterSpacing: 0.5),
    titleMedium: const TextStyle().copyWith(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.black,),
    titleSmall: const TextStyle().copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.black,),

    bodyLarge: const TextStyle().copyWith(fontSize: 16, fontWeight: FontWeight.normal, color: AppColors.black,),
    bodyMedium: const TextStyle().copyWith(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.black,),
    bodySmall: const TextStyle().copyWith(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.black,),

    labelLarge: const TextStyle().copyWith(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.black, letterSpacing: 1.0),
    labelMedium: const TextStyle().copyWith(fontSize: 10, fontWeight: FontWeight.normal, color: AppColors.black.withOpacity(0.5), letterSpacing: 1.0),
  );

  /// Customizable Dark Text Theme
  static TextTheme darkTextTheme = TextTheme(
    headlineLarge: const TextStyle().copyWith(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.white),
    headlineMedium: const TextStyle().copyWith(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.white),
    headlineSmall: const TextStyle().copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.white),

    titleLarge: const TextStyle().copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.white),
    titleMedium: const TextStyle().copyWith(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.white),
    titleSmall: const TextStyle().copyWith(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.white),

    bodyLarge: const TextStyle().copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.white),
    bodyMedium: const TextStyle().copyWith(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.white),
    bodySmall: const TextStyle().copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.white.withOpacity(0.5)),

    labelLarge: const TextStyle().copyWith(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.white),
    labelMedium: const TextStyle().copyWith(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.white.withOpacity(0.5)),
  );
}
