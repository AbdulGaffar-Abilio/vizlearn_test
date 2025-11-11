import 'package:flutter/material.dart';
import 'package:hologram_test/utils/app_export.dart';

import '../utils/constants/colors.dart';
import '../utils/constants/sizes.dart';


class AppDecoration {
  // Outline decorations
  static BoxDecoration get outlineOnPrimaryContainer => BoxDecoration(
        color: AppColors.background2,
        border: Border.all(
          color: AppColors.primary2,
          width: 1,
          strokeAlign: strokeAlignOutside,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.lightGrey,
            spreadRadius: 2,
            blurRadius: 2,
            offset: Offset(
              0,
              1,
            ),
          ),
        ],
      );

  static BoxDecoration get outlinePrimary => BoxDecoration(
      color: AppColors.primary2,
      border: Border.all(
        color: AppColors.primary,
        width: 1,
        strokeAlign: strokeAlignOutside,
      ),
      borderRadius: BorderRadiusStyle.border12);

  static BoxDecoration get outlineGrey => BoxDecoration(
      color: AppColors.white,
      border: Border.all(
        color: AppColors.borderSecondary,
        width: 1,
        strokeAlign: BorderSide.strokeAlignCenter,
      ),
      borderRadius: BorderRadiusStyle.radius8,
      boxShadow: shadow1_4,
  );

  // shadows
  static List<BoxShadow> get shadow1_1 => const [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.25), // rgba(0, 0, 0, 0.25)
      offset: Offset(0, 0),                 // x: 0, y: 0
      blurRadius: 4,                        // blur-radius: 4
      spreadRadius: 0,                      // spread-radius: 0
    ),
  ];


  static List<BoxShadow> get shadow1_2 => const [
        BoxShadow(
          color: Color(0x0A000000),
          spreadRadius: 0,
          blurRadius: 3,
          offset: Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadow1_3 => const [
        BoxShadow(
          color: Color(0x38414A26),
          spreadRadius: 0,
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadow1_4 => [
        const BoxShadow(
          color: AppColors.shadow1,
          blurRadius: 4,
          offset: Offset(0, 0.5),
        ),
      ];

//   // Fill decorations
  static BoxDecoration get fillDeepOrange => const BoxDecoration(
        color: AppColors.background3,
      );

  static BoxDecoration get fillWhite => const BoxDecoration(
        color: AppColors.white,
      );

  static BoxDecoration get fillBG2 => const BoxDecoration(
        color: AppColors.background2,
      );
}

//
class BorderRadiusStyle {
  static BorderRadius get radius8 => BorderRadius.circular(
        AppSizes.borderRadiusSm,
      );

  static BorderRadius get border12 => BorderRadius.circular(
        AppSizes.borderRadiusMd,
      );

  static BorderRadius get border16 => BorderRadius.circular(
        AppSizes.borderRadiusLg,
      );

  static BorderRadius get border32 => BorderRadius.vertical(
        top: Radius.circular(32),
      );
}

// Comment/Uncomment the below code based on your Flutter SDK version.
// For Flutter SDK Version 3.7.2 or greater.

double get strokeAlignOutside => BorderSide.strokeAlignOutside;

// For Flutter SDK Version 3.7.1 or less.

// // StrokeAlign get strokeAlignOutside => StrokeAlign.outside;
