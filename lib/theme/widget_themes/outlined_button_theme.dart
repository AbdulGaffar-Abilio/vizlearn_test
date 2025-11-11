import 'package:flutter/material.dart';
import 'package:hologram_test/utils/app_export.dart';

import '../../utils/constants/colors.dart';
import '../../utils/constants/sizes.dart';

/* -- Light & Dark Outlined Button Themes -- */
class AppOutlinedButtonTheme {
  AppOutlinedButtonTheme._(); //To avoid creating instances


  /* -- Light Theme -- */
  static final lightOutlinedButtonTheme  = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      elevation: 0,
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.borderPrimary),
      textStyle: TextStyle(fontSize: 16, color: AppColors.primary, fontWeight: FontWeight.w500),
      padding:  const EdgeInsets.symmetric(vertical: AppSizes.buttonPadding, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
    ),
  );

  /* -- Dark Theme -- */
  static final darkOutlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.borderPrimary),
      textStyle: const TextStyle(fontSize: 16, color: AppColors.primary, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(vertical: AppSizes.buttonPadding, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
    ),
  );
}
