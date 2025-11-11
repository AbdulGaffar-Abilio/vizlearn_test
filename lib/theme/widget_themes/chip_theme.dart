import 'package:hologram_test/utils/constants/colors.dart';
import 'package:flutter/material.dart';

class AppChipTheme {
  AppChipTheme._();

  static ChipThemeData lightChipTheme = ChipThemeData(
    selectedColor: AppColors.primary, // Primary color for selected chip
    backgroundColor: AppColors.white, // Background color for unselected chip
    labelStyle: const TextStyle(color: AppColors.primary), // Text color for unselected chip
    secondarySelectedColor: AppColors.primary, // Color for selected state
    selectedShadowColor: AppColors.primary.withOpacity(0.4),
    shadowColor: Colors.grey.withOpacity(0.5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // Custom chip shape
      side: const BorderSide(color: AppColors.primary, width: 1), // Border color for unselected
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Chip padding
    secondaryLabelStyle: const TextStyle(color: Colors.white), // Text color for selected chip
    showCheckmark: false,
  );

  static ChipThemeData darkChipTheme = ChipThemeData(
    selectedColor: Colors.white, // Selected chip background
    backgroundColor: AppColors.primary, // Unselected background color
    labelStyle: const TextStyle(color: Colors.white), // Text color for unselected chip
    secondarySelectedColor: Colors.white, // Color for selected state
    selectedShadowColor: Colors.white.withOpacity(0.4),
    shadowColor: Colors.black.withOpacity(0.5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Colors.white, width: 1), // Border for dark mode
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    secondaryLabelStyle: const TextStyle(color: AppColors.primary), // Text color for selected chip
    showCheckmark: false,
  );
}

