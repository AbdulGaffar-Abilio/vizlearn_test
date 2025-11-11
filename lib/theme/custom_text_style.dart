import 'package:flutter/material.dart';
import 'package:hologram_test/utils/app_export.dart';
import 'package:hologram_test/utils/constants/colors.dart';
import 'package:hologram_test/theme/theme.dart';

/// A collection of pre-defined text styles for customizing text appearance,
/// categorized by different font families and weights.
/// Additionally, this class includes extensions on [TextStyle] to easily apply specific font families to text.
//
class CustomTextStyles {
  // Heading styles
  static TextStyle get h1 {
    return theme.textTheme.headlineLarge!.copyWith(
      fontSize: 56,
      fontWeight: FontWeight.bold,
      height: 64 / 56, // Line height is 64px, font size is 56px
      color: AppColors.black,
    );
  }

  static TextStyle get h2 {
    return theme.textTheme.headlineLarge!.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.bold,
      height: 48 / 40, // Line height is 48px, font size is 40px
      color: AppColors.black,
    );
  }

  static TextStyle get h3 {
    return theme.textTheme.headlineLarge!.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.bold, // SemiBold
      height: 38 / 32, // Line height is 42px, font size is 32px
      color: AppColors.black,
    );
  }
  static TextStyle get h3_1 {
    return theme.textTheme.headlineLarge!.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w600, // SemiBold
      height: 38 / 32, // Line height is 42px, font size is 32px
      color: AppColors.black,
    );
  }

  static TextStyle get h4 {
    return theme.textTheme.headlineMedium!.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w600, // SemiBold
      height: 36 / 28, // Line height is 36px, font size is 28px
      color: AppColors.black,
    );
  }

  static TextStyle get h5 {
    return theme.textTheme.headlineMedium!.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600, // Regular
      height: 32 / 24, // Line height is 32px, font size is 24px
      color: AppColors.black,
    );
  }


  static TextStyle get h6 {
    return theme.textTheme.titleLarge!.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      height: 26 / 20, // Line height is 26px, font size is 20px
      color: AppColors.black,
    );
  }

  // Body text styles
  static TextStyle get b1 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600, // Medium
      height: 22 / 18, // Line height is 28px, font size is 18px
      color: AppColors.black,
    );
  }

  static TextStyle get b2 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.bold, // Medium
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.black,
    );
  }
  static TextStyle get b2_1 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600, // Medium
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.black,
    );
  }

  static TextStyle get b3 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.normal, // Regular
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.black,
    );
  }

  static TextStyle get b3_1 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.normal, // Regular
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.white,
    );
  }

  static TextStyle get b3_2 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500, // Regular
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.black,
    );
  }

  static TextStyle get b3_primary {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.normal, // Regular
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.primary,
    );
  }

  static TextStyle get b3_primary1 {
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500, // Regular
      height: 20 / 16, // Line height is 24px, font size is 16px
      color: AppColors.primary,
    );
  }

  static TextStyle get b4 {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600, // Regular
      height: 18 / 14,
      color: AppColors.black,
    );
  }

  static TextStyle get b4Primary {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600, // Regular
      height: 18 / 14,
      color: AppColors.primary,
    );
  }


  static TextStyle get b4Primary2 {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500, // Medium
      height: 18 / 14, // Line height is 21px, font size is 14px
      color: AppColors.primary2,
    );
  }

  static TextStyle get b4_1 {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500, // Medium
      height: 18 / 14, // Line height is 21px, font size is 14px
      color: AppColors.black,
    );
  }

  static TextStyle get b4Underlined {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      // Medium
      height: 18 / 14,
      // Line height is 21px, font size is 14px
      color: Colors.transparent,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.darkGrey,
      shadows: [const Shadow(color: AppColors.darkGrey, offset: Offset(0, -1.3))],
    );
  }
  static TextStyle get b4UnderlinedBlack {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      // Medium
      height: 18 / 14,
      // Line height is 21px, font size is 14px
      color: Colors.transparent,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.darkerGrey,
      shadows: [const Shadow(color: AppColors.darkerGrey, offset: Offset(0, -1.3))],
    );
  }

  static TextStyle get b4UnderlinedPrimary {
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      // Medium
      height: 18 / 14,
      // Line height is 21px, font size is 14px
      color: Colors.transparent,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
      shadows: [const Shadow(color: AppColors.primary, offset: Offset(0, -1.3))],
    );
  }

  static TextStyle get b5 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 18 / 14,
      color: AppColors.black,
    );
  }

  static TextStyle get b5_1 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      height: 18 / 14,
      color: AppColors.black,
    );
  }

  static TextStyle get b6 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 14 / 12,
      color: AppColors.black,
    );
  }

  static TextStyle get b6_1 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 14 / 12,
      color: AppColors.black,
    );
  }

  static TextStyle get b6_2 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 14 / 12,
      color: AppColors.black,
    );
  }

  static TextStyle get b6_3 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 14 / 12,
      //color: AppColors.grey1,
    );
  }

  static TextStyle get b6_primary{
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      height: 14 / 12,
      color: AppColors.primary,
    );
  }

  static TextStyle get b7 {
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.normal,
      height: 14 / 12,
      color: AppColors.darkerGrey,
    );
  }
}
