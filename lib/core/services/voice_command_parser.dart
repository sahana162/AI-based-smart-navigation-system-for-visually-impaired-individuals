import '../../models/voice_command.dart';

class VoiceCommandParser {
  static VoiceCommand parse(String rawText, String assistantName) {
    if (rawText.trim().isEmpty) {
      return const VoiceCommand(
        type: VoiceCommandType.none,
        rawText: '',
      );
    }

    // Remove common punctuation while preserving Kannada and Unicode letters.
    final clean = rawText
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'''[.,!?;:"'()\[\]/\\]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ');

    final nameClean = assistantName.trim().toLowerCase();

    // Check and strip assistant name prefix (English and Kannada prefixes).
    String normalized = clean;
    final prefixes = [
      'hey $nameClean',
      'ok $nameClean',
      'okay $nameClean',
      'hi $nameClean',
      'hello $nameClean',
      'ಹೇ $nameClean',
      'ಹಲೋ $nameClean',
      'ನಮಸ್ಕಾರ $nameClean',
      nameClean,
      'hey lux',
      'ok lux',
      'okay lux',
      'hi lux',
      'hello lux',
      'lux',
      'ಹೇ ಲಕ್ಸ್',
      'ಲಕ್ಸ್',
      'hey gemini',
      'ok gemini',
      'gemini',
      'ಜೆಮಿನಿ',
      'ಹೇ ಜೆಮಿನಿ',
      'ಹಲೋ ಜೆಮಿನಿ',
      'ನಮಸ್ಕಾರ ಜೆಮಿನಿ',
    ];

    for (final prefix in prefixes) {
      if (normalized.startsWith('$prefix ')) {
        normalized = normalized.substring(prefix.length).trim();
        break;
      } else if (normalized == prefix) {
        return VoiceCommand(
          type: VoiceCommandType.startListening,
          rawText: rawText,
        );
      }
    }

    // 1. Language Switching (English & Kannada).
    if (_matches(normalized, [
      'switch to kannada',
      'change to kannada',
      'change language to kannada',
      'kannada',
      'ಕನ್ನಡ',
      'ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಿ',
      'ಕನ್ನಡ ಭಾಷೆ',
      'ಕನ್ನಡದಲ್ಲಿ ಮಾತನಾಡಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.switchLanguage,
        rawText: rawText,
        argument: 'kn',
      );
    }

    if (_matches(normalized, [
      'switch to english',
      'change to english',
      'change language to english',
      'english',
      'ಇಂಗ್ಲಿಷ್',
      'ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸಿ',
      'ಇಂಗ್ಲಿಷ್ ಭಾಷೆ',
      'ಇಂಗ್ಲಿಷ್‌ನಲ್ಲಿ ಮಾತನಾಡಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.switchLanguage,
        rawText: rawText,
        argument: 'en',
      );
    }

    // 2. Take Me To [Destination] / Navigate To [Destination]
    if (normalized == 'go back' || normalized == 'back' || normalized == 'ಹಿಂದೆ' || normalized == 'ಹಿಂದೆ ಹೋಗಿ') {
      return VoiceCommand(
        type: VoiceCommandType.goBack,
        rawText: rawText,
      );
    }

    final navPrefixes = [
      'can you help me find the ',
      'can you help me find a ',
      'can you help me find ',
      'help me find the ',
      'help me find a ',
      'help me find ',
      'i want to go to ',
      'i want to walk to ',
      'i need to go to ',
      'how do i get to ',
      'how to get to ',
      'how do i reach ',
      'take me to ',
      'take me ',
      'navigate to ',
      'directions to ',
      'go to ',
      'go ',
      'walk to ',
      'walk ',
      'route to ',
      'head to ',
      'heading to ',
      'ಕರೆದೊಯ್ಯಿರಿ ',
      'ದಾರಿ ತೋರಿಸಿ ',
    ];
    for (final prefix in navPrefixes) {
      if (normalized.startsWith(prefix)) {
        final destination = normalized.substring(prefix.length).trim();
        // If query began with 'help me find', ensure it refers to a place/transit point, not personal belongings
        if (prefix.contains('help me find')) {
          final lowerDest = destination.toLowerCase();
          final isBelonging = lowerDest.contains('bottle') ||
              lowerDest.contains('phone') ||
              lowerDest.contains('laptop') ||
              lowerDest.contains('keys') ||
              lowerDest.contains('chair') ||
              lowerDest.contains('cup') ||
              lowerDest.contains('backpack') ||
              lowerDest.contains('bag') ||
              lowerDest.contains('wallet') ||
              lowerDest.contains('glasses');
          if (isBelonging) {
            continue; // Handled by findItem
          }
        }
        if (destination.isNotEmpty) {
          return VoiceCommand(
            type: VoiceCommandType.takeMeTo,
            rawText: rawText,
            argument: destination,
          );
        }
      }
    }

    // Kannada natural SOV navigation syntax (e.g. "ಮೆಜೆಸ್ಟಿಕ್ ಗೆ ದಾರಿ ತೋರಿಸಿ" / "ಆಸ್ಪತ್ರೆಗೆ ಕರೆದೊಯ್ಯಿರಿ")
    final kannadaNavSuffixes = [
      'ದಾರಿ ತೋರಿಸಿ',
      'ದಾರಿ ತೋರು',
      'ಕರೆದೊಯ್ಯಿರಿ',
      'ಕರೆದುಕೊಂಡು ಹೋಗು',
      'ಹೋಗಬೇಕು',
    ];
    for (final suffix in kannadaNavSuffixes) {
      if (normalized.endsWith(suffix) && normalized.length > suffix.length) {
        String destination = normalized.substring(0, normalized.length - suffix.length).trim();
        destination = destination.replaceAll(RegExp(r'(ಕ್ಕೆ|ಗೆ|ನ್ನು|ಗೆ ಹೋಗಲು|ಗೆ ದಾರಿ)$'), '').trim();
        if (destination.isNotEmpty) {
          return VoiceCommand(
            type: VoiceCommandType.takeMeTo,
            rawText: rawText,
            argument: destination,
          );
        }
      }
    }

    // 3. Where Am I? / Current Location
    if (!normalized.startsWith('save') &&
        !normalized.startsWith('set') &&
        !normalized.startsWith('ಉಳಿಸು') &&
        _matches(normalized, [
      'where am i',
      'what is my location',
      'current location',
      'where is this',
      'what place is this',
      'my location',
      'tell me my location',
      'ನಾನು ಎಲ್ಲಿದ್ದೇನೆ',
      'ನನ್ನ ಸ್ಥಳ ಯಾವುದು',
      'ಪ್ರಸ್ತುತ ಸ್ಥಳ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.whereAmI,
        rawText: rawText,
      );
    }

    // 3b. Around Me / Nearby Amenities Spatial Exploration
    if (_matches(normalized, [
      'what is around me',
      'whats around me',
      'around me',
      'explore around me',
      'explore nearby',
      'nearby places',
      'nearby amenities',
      'what places are near me',
      'places around here',
      'what is near me',
      'whats near me',
      'explore area',
      'ಏನಿದೆ ಸುತ್ತಮುತ್ತ',
      'ಸುತ್ತಮುತ್ತ ಏನಿದೆ',
      'ಸುತ್ತಲಿನ ಸ್ಥಳಗಳು',
      'ಸುತ್ತಮುತ್ತಲಿನ ಸ್ಥಳಗಳು',
      'ಹತ್ತಿರದ ಸ್ಥಳಗಳು',
      'ಸುತ್ತಲೂ ಏನಿದೆ',
      'ಸುತ್ತಮುತ್ತ ನೋಡು',
      'ಸುತ್ತಮುತ್ತ ನೋಡಿ',
      'ಸುತ್ತಮುತ್ತ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.aroundMe,
        rawText: rawText,
      );
    }

    // 3c. Facing Direction / Compass Orientation
    if (_matches(normalized, [
      'which way am i facing',
      'which way am i looking',
      'what direction am i facing',
      'what direction am i looking',
      'what direction am i heading',
      'which direction am i facing',
      'what is my heading',
      'what heading am i',
      'compass heading',
      'compass direction',
      'facing direction',
      'which direction',
      'what direction',
      'which way',
      'compass',
      'orientation',
      'ಯಾವ ದಿಕ್ಕಿಗೆ ಮುಖ ಮಾಡಿದ್ದೇನೆ',
      'ಯಾವ ದಿಕ್ಕಿಗೆ ನೋಡುತ್ತಿದ್ದೇನೆ',
      'ಯಾವ ದಿಕ್ಕು',
      'ದಿಕ್ಕು ಯಾವುದು',
      'ದಿಕ್ಕು',
      'ದಿಕ್ಸೂಚಿ',
      'ಯಾವ ಕಡೆ ಮುಖ ಮಾಡಿದ್ದೇನೆ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.facingDirection,
        rawText: rawText,
      );
    }

    // 4. Start Navigation (Camera / Visual).
    if (_matches(normalized, [
      'start navigation',
      'start navigate',
      'start navigating',
      'open navigation',
      'begin navigation',
      'start camera',
      'navigate',
      'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ',
      'ನ್ಯಾವಿಗೇಷನ್ ಶುರು',
      'ಪ್ರಾರಂಭಿಸಿ',
      'ಕ್ಯಾಮೆರಾ ತೆರೆ',
      'ಕ್ಯಾಮೆರಾ ತೆರೆಯಿರಿ',
      'ಶುರುಮಾಡು',
      'ಕ್ಯಾಮೆರಾ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.startNavigation,
        rawText: rawText,
      );
    }

    // 5. Stop Navigation.
    if (_matches(normalized, [
      'stop navigation',
      'stop navigating',
      'cancel navigation',
      'exit navigation',
      'close navigation',
      'end navigation',
      'quit navigation',
      'ನ್ಯಾವಿಗೇಷನ್ ನಿಲ್ಲಿಸಿ',
      'ಕ್ಯಾಮೆರಾ ಮುಚ್ಚಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.stopNavigation,
        rawText: rawText,
      );
    }

    // 6. Describe Surroundings / Scene.
    if (_matches(normalized, [
      'what can you see',
      'what do you see',
      'what can you see in front of me',
      'what am i looking at',
      'what am i looking towards',
      'what am i facing',
      'what is in front of me',
      'whats in front of me',
      'what do you see in front of me',
      'what am i seeing',
      'describe what you see',
      'describe my surroundings',
      'describe surroundings',
      'describe the scene',
      'describe scene',
      'tell me what you see',
      'look around',
      'surroundings',
      'scene description',
      'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ',
      'ಏನಿದೆ ಮುಂದೆ',
      'ವಿವರಣೆ ನೀಡಿ',
      'ವಿವರಣೆ',
      'ನೋಡು',
      'ಮುಂದೆ ಏನಿದೆ',
      'ದೃಶ್ಯ ವಿವರಣೆ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.describeSurroundings,
        rawText: rawText,
      );
    }

    // 7b. Toggle Live Obstacle Alerts (evaluated before generic obstacle detection).
    if (_matches(normalized, [
      'start obstacle alerts',
      'stop obstacle alerts',
      'pause obstacle alerts',
      'resume obstacle alerts',
      'toggle obstacle alerts',
      'obstacle alerts',
      'live alerts',
      'pause alerts',
      'resume alerts',
      'start alerts',
      'stop alerts',
      'ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆ',
      'ಎಚ್ಚರಿಕೆ ನಿಲ್ಲಿಸಿ',
      'ಎಚ್ಚರಿಕೆ ಪ್ರಾರಂಭಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleObstacleAlerts,
        rawText: rawText,
      );
    }

    // 7. Detect Objects / Obstacles.
    if (_matches(normalized, [
      'detect objects',
      'detect object',
      'detect obstacles',
      'detect obstacle',
      'check obstacles',
      'check for obstacles',
      'obstacle detection',
      'is there any obstacle',
      'is there anything in front of me',
      'what is in front of me',
      'what is in my way',
      'scan for obstacles',
      'what objects are in front of me',
      'find obstacles',
      'identify objects',
      'look for obstacles',
      'obstacles',
      'obstacle',
      'ವಸ್ತುಗಳನ್ನು ಪತ್ತೆ ಮಾಡಿ',
      'ಅಡೆತಡೆಗಳನ್ನು ಗುರುತಿಸಿ',
      'ಅಡೆತಡೆ ಪತ್ತೆ',
      'ಮುಂದೆ ಏನಿದೆ',
      'ವಸ್ತು ಪತ್ತೆ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.detectObjects,
        rawText: rawText,
      );
    }

    // 7c. Toggle Camera Torch / Flashlight.
    if (_matches(normalized, [
      'turn on torch',
      'turn on flashlight',
      'turn on the torch',
      'turn on the flashlight',
      'turn on light',
      'torch on',
      'flashlight on',
      'light on',
      'start torch',
      'enable torch',
      'enable flashlight',
      'ಟಾರ್ಚ್ ಆನ್ ಮಾಡಿ',
      'ಟಾರ್ಚ್ ಆನ್',
      'ಬೆಳಕು ಆನ್ ಮಾಡಿ',
      'ಬೆಳಕು ಆನ್',
      'ಫ್ಲ್ಯಾಶ್‌ಲೈಟ್ ಆನ್',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleTorch,
        rawText: rawText,
        argument: 'on',
      );
    }

    if (_matches(normalized, [
      'turn off torch',
      'turn off flashlight',
      'turn off the torch',
      'turn off the flashlight',
      'turn off light',
      'torch off',
      'flashlight off',
      'light off',
      'stop torch',
      'disable torch',
      'disable flashlight',
      'ಟಾರ್ಚ್ ಆಫ್ ಮಾಡಿ',
      'ಟಾರ್ಚ್ ಆಫ್',
      'ಬೆಳಕು ಆಫ್ ಮಾಡಿ',
      'ಬೆಳಕು ಆಫ್',
      'ಫ್ಲ್ಯಾಶ್‌ಲೈಟ್ ಆಫ್',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleTorch,
        rawText: rawText,
        argument: 'off',
      );
    }

    if (_matches(normalized, [
      'toggle torch',
      'toggle flashlight',
      'toggle light',
      'torch',
      'flashlight',
      'ಟಾರ್ಚ್',
      'ಫ್ಲ್ಯಾಶ್‌ಲೈಟ್',
      'ಬೆಳಕು',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleTorch,
        rawText: rawText,
      );
    }

    // 8b. Read Bus Number / Transit Route (checked before general read text).
    if (_matches(normalized, [
      'what bus is this',
      'which bus is this',
      'which bus is coming',
      'what bus is coming',
      'read bus number',
      'read bus route',
      'read bus board',
      'bus number',
      'bus route',
      'bus board',
      'check bus',
      'detect bus',
      'transit',
      'bus',
      'ಯಾವ ಬಸ್ ಬರುತ್ತಿದೆ',
      'ಯಾವ ಬಸ್',
      'ಬಸ್ ಬರುತ್ತಿದೆಯೇ',
      'ಬಸ್ ಸಂಖ್ಯೆ ಓದಿ',
      'ಬಸ್ ಸಂಖ್ಯೆ',
      'ಬಸ್ ನಂಬರ್ ಎಷ್ಟು',
      'ಬಸ್ ನಂಬರ್',
      'ಬಸ್ ಬೋರ್ಡ್ ಓದಿ',
      'ಬಸ್ ಬೋರ್ಡ್',
      'ಬಸ್ ಓದಿ',
      'ಬಸ್ ರೂಟ್',
      'ಬಸ್',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.readBusRoute,
        rawText: rawText,
      );
    }

    // 8. Read Text (OCR).
    if (_matches(normalized, [
      'read everything',
      'read all text',
      'read all',
      'read full text',
      'read entire page',
      'read everything in front of me',
      'ಎಲ್ಲಾ ಓದಿ',
      'ಪೂರ್ಣ ಪಠ್ಯ ಓದಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.readText,
        rawText: rawText,
        argument: 'all',
      );
    }

    if (_matches(normalized, [
      'continue reading',
      'keep reading',
      'read more',
      'ಮುಂದೆ ಓದಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.readText,
        rawText: rawText,
        argument: 'continue',
      );
    }

    if (_matches(normalized, [
      'read the sign in front of me',
      'read the sign',
      'read this sign',
      'read sign',
      'read this text',
      'read text',
      'read this',
      'read words',
      'read document',
      'read paper',
      'what does the sign say',
      'what does it say',
      'what does that say',
      'read',
      'ocr',
      'scan text',
      'text reader',
      'ಪಠ್ಯ ಓದಿ',
      'ಓದಿ',
      'ಓದು',
      'ಬರೆಹ ಓದು',
      'ಅಕ್ಷರ ಓದಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.readText,
        rawText: rawText,
        argument: 'smart',
      );
    }

    // 8c. Traffic Light / Crossing Signal Color.
    if (_matches(normalized, [
      'check traffic light',
      'check traffic signal',
      'check signal',
      'what color is the traffic light',
      'what color is the light',
      'what color is the signal',
      'is the light red or green',
      'is the signal red or green',
      'traffic light',
      'traffic signal',
      'signal color',
      'is it safe to cross',
      'can i cross',
      'cross road',
      'pedestrian crossing',
      'crossing signal',
      'ಟ್ರ್ಯಾಫಿಕ್ ಲೈಟ್ ಚೆಕ್ ಮಾಡು',
      'ಟ್ರ್ಯಾಫಿಕ್ ಲೈಟ್',
      'ರಸ್ತೆ ದಾಟಲು ಸುರಕ್ಷಿತವೇ',
      'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಿ',
      'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್',
      'ಸಿಗ್ನಲ್ ಕೆಂಪಾಗಿದೆಯೇ',
      'ಸಿಗ್ನಲ್ ಹಸೀರಾಗಿದೆಯೇ',
      'ಸಿಗ್ನಲ್ ಬಣ್ಣ ಏನು',
      'ಸಿಗ್ನಲ್ ಬಣ್ಣ',
      'ರಸ್ತೆ ದಾಟಬಹುದೇ',
      'ದಾಟಬಹುದೇ',
      'ಟ್ರಾಫಿಕ್ ಲೈಟ್',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.checkTrafficLight,
        rawText: rawText,
      );
    }

    // 9. Recognize Currency (Notes & Coins).
    if (_matches(normalized, [
      'recognize currency',
      'detect currency',
      'check currency',
      'scan currency',
      'read currency',
      'currency recognition',
      'currency detection',
      'currency',
      'read note',
      'detect note',
      'check note',
      'scan note',
      'identify note',
      'what note is this',
      'what bill is this',
      'check bill',
      'detect bill',
      'banknote',
      'what coin is this',
      'check coin',
      'detect coin',
      'scan coin',
      'read coin',
      'identify coin',
      'coin',
      'coins',
      'what rupee is this',
      'how many rupees',
      'how much money is this',
      'check money',
      'read money',
      'count currency',
      'identify cash',
      'money',
      'cash',
      'rupees',
      'rupee',
      'ಕರೆನ್ಸಿ ಗುರುತಿಸಿ',
      'ಕರೆನ್ಸಿ ಪರಿಶೀಲಿಸಿ',
      'ಕರೆನ್ಸಿ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ',
      'ಕರೆನ್ಸಿ',
      'ನೋಟು ಗುರುತಿಸಿ',
      'ನೋಟು ಪರಿಶೀಲಿಸಿ',
      'ನೋಟು ಓದಿ',
      'ನೋಟು',
      'ನಾಣ್ಯ ಗುರುತಿಸಿ',
      'ನಾಣ್ಯ ಪರಿಶೀಲಿಸಿ',
      'ನಾಣ್ಯ ಓದಿ',
      'ನಾಣ್ಯ',
      'ಹಣ ಗುರುತಿಸಿ',
      'ಹಣ ಪರಿಶೀಲಿಸಿ',
      'ಹಣ',
      'ಇದು ಎಷ್ಟು ರೂಪಾಯಿ',
      'ಎಷ್ಟು ರೂಪಾಯಿ',
      'ರೂಪಾಯಿ ಪರಿಶೀಲಿಸಿ',
      'ರೂಪಾಯಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.recognizeCurrency,
        rawText: rawText,
      );
    }

    // 9b. Save Favorite Place (Home / Work).
    if (_matches(normalized, [
      'save current location as home',
      'save location as home',
      'set current location as home',
      'set location as home',
      'save as home',
      'set as home',
      'save home',
      'ಈ ಸ್ಥಳವನ್ನು ಮನೆ ಎಂದು ಉಳಿಸಿ',
      'ಪ್ರಸ್ತುತ ಸ್ಥಳವನ್ನು ಮನೆ ಎಂದು ಉಳಿಸಿ',
      'ಸ್ಥಳವನ್ನು ಮನೆ ಎಂದು ಉಳಿಸಿ',
      'ಮನೆ ಎಂದು ಉಳಿಸಿ',
      'ಮನೆಯಾಗಿ ಉಳಿಸು',
      'ಮನೆ ಎಂದು ಉಳಿಸು',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.saveFavoritePlace,
        rawText: rawText,
        argument: 'home',
      );
    }

    if (_matches(normalized, [
      'save current location as work',
      'save location as work',
      'set current location as work',
      'set location as work',
      'save as work',
      'set as work',
      'save work',
      'save office',
      'set office',
      'ಈ ಸ್ಥಳವನ್ನು ಕಚೇರಿ ಎಂದು ಉಳಿಸಿ',
      'ಪ್ರಸ್ತುತ ಸ್ಥಳವನ್ನು ಕಚೇರಿ ಎಂದು ಉಳಿಸಿ',
      'ಸ್ಥಳವನ್ನು ಕಚೇರಿ ಎಂದು ಉಳಿಸಿ',
      'ಕಚೇರಿ ಎಂದು ಉಳಿಸಿ',
      'ಕಚೇರಿಯಾಗಿ ಉಳಿಸು',
      'ಕಚೇರಿ ಎಂದು ಉಳಿಸು',
      'ಆಫೀಸ್ ಎಂದು ಉಳಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.saveFavoritePlace,
        rawText: rawText,
        argument: 'work',
      );
    }

    // 9b. Enroll Friend / Save Friend's Face
    final enrollFriendPrefixes = [
      'remember this face as ',
      'remember face as ',
      'remember this person as ',
      'remember person as ',
      'save this face as ',
      'save face as ',
      'save friend ',
      'save my friend ',
      'this is my friend ',
      'this is friend ',
      'add friend ',
      'ಮುಖ ನೆನಪಿಡಿ ',
    ];
    for (final prefix in enrollFriendPrefixes) {
      if (normalized.startsWith(prefix)) {
        final name = normalized.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          return VoiceCommand(
            type: VoiceCommandType.enrollFriend,
            rawText: rawText,
            argument: name,
          );
        }
      }
    }

    if (normalized.startsWith('ಸ್ನೇಹಿತ ')) {
      String name = normalized.substring('ಸ್ನೇಹಿತ '.length).trim();
      if (name.endsWith(' ಉಳಿಸಿ')) {
        name = name.substring(0, name.length - ' ಉಳಿಸಿ'.length).trim();
      } else if (name.endsWith(' ಸೇವ್ ಮಾಡಿ')) {
        name = name.substring(0, name.length - ' ಸೇವ್ ಮಾಡಿ'.length).trim();
      }
      if (name.isNotEmpty) {
        return VoiceCommand(
          type: VoiceCommandType.enrollFriend,
          rawText: rawText,
          argument: name,
        );
      }
    }

    // 9c. Who Is Here / Proximity & Face Identification
    if (_matches(normalized, [
      'who is in front of me',
      'who is that',
      'who is this',
      'who is here',
      'who is there',
      'who is approaching',
      'who is coming',
      'who is standing in front of me',
      'ಯಾರಿದು',
      'ಮುಂದೆ ಯಾರು ಇದ್ದಾರೆ',
      'ಯಾರು ಮುಂದಿದ್ದಾರೆ',
      'ಯಾರು ಇಲ್ಲಿದ್ದಾರೆ',
      'ಯಾರು ಅದು',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.whoIsHere,
        rawText: rawText,
      );
    }

    // 10. Save Item.
    final savePrefixes = [
      'save this item',
      'save item',
      'save ',
      'remember this item',
      'remember ',
      'ವಸ್ತು ಉಳಿಸಿ',
      'ನೆನಪಿಟ್ಟುಕೊ ',
    ];
    for (final prefix in savePrefixes) {
      if (normalized.startsWith(prefix)) {
        final item = normalized.substring(prefix.length).trim();
        return VoiceCommand(
          type: VoiceCommandType.saveItem,
          rawText: rawText,
          argument: item.isNotEmpty ? item : null,
        );
      }
    }

    final kannadaSaveSuffixes = [
      'ನೆನಪಿಟ್ಟುಕೊಳ್ಳಿ',
      'ನೆನಪಿಟ್ಟುಕೊ',
      'ನೆನಪಿಡಿ',
      'ಉಳಿಸಿ',
      'ಸೇವ್ ಮಾಡಿ',
    ];
    for (final suffix in kannadaSaveSuffixes) {
      if (normalized.endsWith(suffix) && normalized.length > suffix.length) {
        String item = normalized.substring(0, normalized.length - suffix.length).trim();
        item = item.replaceAll(RegExp(r'(ನ್ನು|ಅನ್ನು|ಯನ್ನು|ವಸ್ತು)$'), '').trim();
        if (item.isNotEmpty) {
          return VoiceCommand(
            type: VoiceCommandType.saveItem,
            rawText: rawText,
            argument: item,
          );
        }
      }
    }

    // 11. Find Item / Find Saved Item / Live Object Search
    final findPrefixes = [
      'can you help me find ',
      'help me find ',
      'can you find a ',
      'can you find an ',
      'can you find ',
      'can you see a ',
      'can you see an ',
      'can you see ',
      'where did i leave ',
      'where did i put ',
      'where are my ',
      'where are ',
      'where is my ',
      'where is ',
      'look for my ',
      'look for ',
      'find my saved item ',
      'find saved item ',
      'find an item ',
      'find a ',
      'find item ',
      'find ',
      'locate ',
      'ಎಲ್ಲಿದೆ ನನ್ನ ',
      'ಎಲ್ಲಿದೆ ',
      'ವಸ್ತು ಹುಡುಕಿ ',
      'ಹುಡುಕಿ ',
    ];
    for (final prefix in findPrefixes) {
      if (normalized.startsWith(prefix)) {
        final item = normalized.substring(prefix.length).trim();
        return VoiceCommand(
          type: VoiceCommandType.findItem,
          rawText: rawText,
          argument: item.isNotEmpty ? item : null,
        );
      }
    }

    // Kannada natural item search syntax (e.g. "ಕೀ ಹುಡುಕಿ" or "ಬಾಟಲ್ ಎಲ್ಲಿದೆ" or "ನನ್ನ ಬಾಟಲ್ ಹುಡುಕು")
    final kannadaFindSuffixes = [
      'ಹುಡುಕಿ',
      'ಹುಡುಕು',
      'ಎಲ್ಲಿದೆ',
      'ಎಲ್ಲಿಟ್ಟಿದ್ದೇನೆ',
    ];
    for (final suffix in kannadaFindSuffixes) {
      if (normalized.endsWith(suffix) && normalized.length > suffix.length) {
        String item = normalized.substring(0, normalized.length - suffix.length).trim();
        item = item.replaceAll(RegExp(r'(ನ್ನು|ನನ್ನು|ಯನ್ನು|ಅನ್ನು)$'), '').trim();
        if (item.startsWith('ನನ್ನ ')) {
          item = item.substring('ನನ್ನ '.length).trim();
        }
        if (item.isNotEmpty) {
          return VoiceCommand(
            type: VoiceCommandType.findItem,
            rawText: rawText,
            argument: item,
          );
        }
      }
    }

    // 14. Find Person / Recognize Person.
    if (_matches(normalized, [
      'find this person',
      'find person',
      'recognize this person',
      'recognize person',
      'identify person',
      'ವ್ಯಕ್ತಿಯನ್ನು ಗುರುತಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.findPerson,
        rawText: rawText,
      );
    }

    // 13. Go Back.
    if (_matches(normalized, [
      'go back',
      'back',
      'previous screen',
      'return to home',
      'go home',
      'close screen',
      'ಹಿಂದೆ ಹೋಗು',
      'ಹಿಂದೆ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.goBack,
        rawText: rawText,
      );
    }

    // 14. Speech Speed Controls.
    if (_matches(normalized, [
      'increase speech speed',
      'speak a little faster',
      'faster speech',
      'speak faster',
      'talk faster',
      'faster please',
      'faster',
      'ವೇಗವಾಗಿ ಮಾತನಾಡಿ',
      'ವೇಗ ಹೆಚ್ಚಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.increaseSpeechSpeed,
        rawText: rawText,
      );
    }

    if (_matches(normalized, [
      'decrease speech speed',
      'speak a little slower',
      'slower speech',
      'speak slower',
      'talk slower',
      'slower please',
      'slower',
      'ನಿಧಾನವಾಗಿ ಮಾತನಾಡಿ',
      'ವೇಗ ಕಡಿಮೆ ಮಾಡಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.decreaseSpeechSpeed,
        rawText: rawText,
      );
    }

    // 15. Listening Session Controls.
    if (_matches(normalized, [
      'start listening',
      'listen',
      'listen to me',
      'wake up',
      'ಕೇಳಿಸಿಕೊಳ್ಳಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.startListening,
        rawText: rawText,
      );
    }

    if (_matches(normalized, [
      'stop listening',
      'cancel listening',
      'stop microphone',
      'done listening',
      'end session',
      'ಮೈಕ್ ಆಫ್ ಮಾಡಿ',
      'ಕೇಳುವುದು ನಿಲ್ಲಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.stopListening,
        rawText: rawText,
      );
    }

    // 16. Repeat.
    if (_matches(normalized, [
      'repeat that please',
      'repeat that',
      'repeat please',
      'repeat',
      'repeat last',
      'say again',
      'say that again',
      'what did you say',
      'pardon',
      'ಮತ್ತೆ ಹೇಳಿ',
      'ಪುನರಾವರ್ತಿಸಿ',
      'ಇನ್ನೊಮ್ಮೆ ಹೇಳಿ',
      'ಮತ್ತೊಮ್ಮೆ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.repeat,
        rawText: rawText,
      );
    }

    // 17. Capability Inquiries (Checked first so questions like "what can you help me with" resolve to help).
    if (_matches(normalized, [
      'what can you help me with',
      'what can you help with',
      'what can i say',
      'commands',
      'what can you do',
      'instructions',
      'options',
      'ಆದೇಶಗಳು',
      'ಏನು ಮಾಡಬಹುದು',
      'ಹೇಗೆ ಬಳಸುವುದು',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.help,
        rawText: rawText,
      );
    }

    // 17b. Battery and System Readiness Status.
    if (_matches(normalized, [
      'battery status',
      'battery level',
      'battery percentage',
      'how much battery',
      'what is the battery',
      'check battery',
      'device status',
      'phone status',
      'system status',
      'status of device',
      'battery',
      'ಬ್ಯಾಟರಿ ಸ್ಥಿತಿ',
      'ಬ್ಯಾಟರಿ ಎಷ್ಟು',
      'ಬ್ಯಾಟರಿ',
      'ಫೋನ್ ಸ್ಥಿತಿ',
      'ಡಿವೈಸ್ ಸ್ಥಿತಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.batteryStatus,
        rawText: rawText,
      );
    }

    // 18. Emergency / SOS (safety critical direct cries).
    if (_matches(normalized, [
      'emergency',
      'emergency assistance',
      'help me',
      'sos',
      'call helper',
      'ತುರ್ತು',
      'ತುರ್ತು ಸಹಾಯ',
      'ಕಾಪಾಡಿ',
      'ಸಹಾಯ ಮಾಡಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.emergency,
        rawText: rawText,
      );
    }

    // 19. General Help
    if (_matches(normalized, [
      'help',
      'ಸಹಾಯ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.help,
        rawText: rawText,
      );
    }

    // 19. Open Settings.
    if (_matches(normalized, [
      'open settings',
      'settings',
      'preferences',
      'assistant settings',
      'configure',
      'ಸೆಟ್ಟಿಂಗ್ಸ್',
      'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ',
      'ಆಯ್ಕೆಗಳು',
      'ಹೆಸರು ಬದಲಾಯಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.openSettings,
        rawText: rawText,
      );
    }

    // 20. Stop Speaking / Silence.
    if (_matches(normalized, [
      'stop speaking',
      'be quiet',
      'silence',
      'quiet',
      'shut up',
      'stop',
      'ಶಾಂತವಾಗಿರಿ',
      'ಮಾತನಾಡಬೇಡಿ',
      'ಸುಮ್ಮನಿರು',
      'ಸಾಕು',
      'ಸ್ಟಾಪ್',
      'ನಿಲ್ಲಿಸಿ',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.stopSpeaking,
        rawText: rawText,
      );
    }

    return VoiceCommand(
      type: VoiceCommandType.unknown,
      rawText: rawText,
    );
  }

  static bool _matches(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (text == pattern ||
          text.startsWith('$pattern ') ||
          text.endsWith(' $pattern') ||
          text.contains(' $pattern ')) {
        return true;
      }
    }
    return false;
  }
}
