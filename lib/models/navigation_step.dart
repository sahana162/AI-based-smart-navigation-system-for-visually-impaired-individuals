/// Represents a single pedestrian navigation instruction step.
class PedestrianStep {
  final String instruction;
  final String streetName;
  final String maneuverType;
  final String maneuverModifier;
  final double distanceMeters;
  final double durationSeconds;
  final double waypointLat;
  final double waypointLng;

  const PedestrianStep({
    required this.instruction,
    required this.streetName,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.waypointLat,
    required this.waypointLng,
  });

  /// Approximate pedestrian steps for this segment (based on 0.75m average stride).
  int get estimatedSteps => (distanceMeters / 0.75).round();

  /// Formatted instruction including estimated step count.
  String formattedInstructionWithSteps({bool isKannada = false}) {
    if (isKannada) {
      return '$instruction (ಸುಮಾರು $estimatedSteps ಹೆಜ್ಜೆಗಳು)';
    }
    return '$instruction (approx $estimatedSteps steps)';
  }

  /// Human-friendly spoken guidance for this step.
  String spokenInstruction({
    double? remainingMeters,
    bool isKannada = false,
    double? relativeBearingDegrees,
  }) {
    final dist = remainingMeters != null ? remainingMeters.round() : distanceMeters.round();
    final clockSuffix = formatClockDirection(relativeBearingDegrees, isKannada: isKannada);

    if (isKannada) {
      if (dist <= 8) {
        if (maneuverType == 'arrive') {
          return 'ನೀವು ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪಿದ್ದೀರಿ.';
        }
        return 'ಈಗ $kannadaManeuverDescription$clockSuffix.';
      } else {
        return '$dist ಮೀಟರ್‌ಗಳಲ್ಲಿ, $kannadaManeuverDescription$clockSuffix.';
      }
    }

    if (dist <= 8) {
      if (maneuverType == 'arrive') {
        return 'You have arrived at your destination.';
      }
      return '$maneuverDescription now$clockSuffix.';
    } else {
      return 'In $dist meters, $maneuverDescription$clockSuffix.';
    }
  }

  String get maneuverDescription {
    if (maneuverType == 'arrive') return 'arrive at your destination';
    if (maneuverType == 'depart') {
      return streetName.isNotEmpty ? 'head out on $streetName' : 'head straight';
    }
    final turn = maneuverModifier.isNotEmpty ? 'turn $maneuverModifier' : 'continue';
    if (streetName.isNotEmpty) {
      return '$turn onto $streetName';
    }
    return turn;
  }

  String get kannadaManeuverDescription {
    if (maneuverType == 'arrive') return 'ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪಿ';
    if (maneuverType == 'depart') {
      return streetName.isNotEmpty ? '$streetName ರಸ್ತೆಯಲ್ಲಿ ಹೊರಡಿ' : 'ನೇರವಾಗಿ ಹೊರಡಿ';
    }
    String turnKn = 'ಮುಂದುವರಿಯಿರಿ';
    final mod = maneuverModifier.toLowerCase();
    if (mod.contains('sharp right')) {
      turnKn = 'ತೀಕ್ಷ್ಣ ಬಲಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('slight right')) {
      turnKn = 'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('right')) {
      turnKn = 'ಬಲಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('sharp left')) {
      turnKn = 'ತೀಕ್ಷ್ಣ ಎಡಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('slight left')) {
      turnKn = 'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('left')) {
      turnKn = 'ಎಡಕ್ಕೆ ತಿರುಗಿ';
    } else if (mod.contains('uturn')) {
      turnKn = 'ಹಿಂತಿರುಗಿ (ಯು-ಟರ್ನ್)';
    }

    if (streetName.isNotEmpty) {
      return '$streetName ಕಡೆಗೆ $turnKn';
    }
    return turnKn;
  }

  /// Calculates clock-face relative direction for blind pedestrian orientation.
  static String formatClockDirection(double? relativeBearing, {bool isKannada = false}) {
    if (relativeBearing == null) return '';
    final angle = (relativeBearing % 360 + 360) % 360;
    if (angle >= 345 || angle < 15) {
      return isKannada ? ' (ನೇರವಾಗಿ ಮುಂದೆ)' : ' (straight ahead)';
    } else if (angle >= 15 && angle < 45) {
      return isKannada ? ' (ಸುಮಾರು 1 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (around 1 o\'clock)';
    } else if (angle >= 45 && angle < 75) {
      return isKannada ? ' (2 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (at 2 o\'clock)';
    } else if (angle >= 75 && angle < 105) {
      return isKannada ? ' (ಬಲಕ್ಕೆ, 3 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (to your right, 3 o\'clock)';
    } else if (angle >= 105 && angle < 150) {
      return isKannada ? ' (ಹಿಂದೆ ಬಲಕ್ಕೆ)' : ' (behind to the right)';
    } else if (angle >= 150 && angle < 210) {
      return isKannada ? ' (ನಿಮ್ಮ ಹಿಂದೆ, ಹಿಂತಿರುಗಿ)' : ' (behind you, turn around)';
    } else if (angle >= 210 && angle < 255) {
      return isKannada ? ' (ಹಿಂದೆ ಎಡಕ್ಕೆ)' : ' (behind to the left)';
    } else if (angle >= 255 && angle < 285) {
      return isKannada ? ' (ಎಡಕ್ಕೆ, 9 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (to your left, 9 o\'clock)';
    } else if (angle >= 285 && angle < 315) {
      return isKannada ? ' (10 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (at 10 o\'clock)';
    } else {
      return isKannada ? ' (ಸುಮಾರು 11 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ)' : ' (around 11 o\'clock)';
    }
  }
}

/// Represents an active pedestrian route.
class PedestrianRoute {
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<PedestrianStep> steps;
  final List<List<double>> polylineCoordinates; // [lat, lng]
  final bool isDirectCompassMode;

  const PedestrianRoute({
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.steps,
    required this.polylineCoordinates,
    this.isDirectCompassMode = false,
  });
}
