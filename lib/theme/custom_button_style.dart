import 'package:flutter/material.dart';
import 'package:hologram_test/utils/app_export.dart';

import '../utils/constants/colors.dart';

/// A class that offers pre-defined button styles for customizing button appearance.
class CustomButtonStyles {
  // text button style
  static ButtonStyle get secondaryButton => ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(AppColors.buttonSecondary),
        side: WidgetStateProperty.all<BorderSide>(
          const BorderSide(color: AppColors.buttonSecondary),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  static ButtonStyle get whiteButton => ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(AppColors.white),
        side: WidgetStateProperty.all<BorderSide>(
          const BorderSide(color: AppColors.white),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

  static ButtonStyle get greyButton => ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(AppColors.darkerGrey),
        side: WidgetStateProperty.all<BorderSide>(
          const BorderSide(color: AppColors.darkerGrey),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

  static ButtonStyle get roundButton => ButtonStyle(
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
    side: WidgetStateProperty.all<BorderSide>(
      const BorderSide(color: AppColors.buttonSecondary),
    ),
      );
}
