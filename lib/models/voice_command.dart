/// Supported voice command types (English and Kannada).
enum VoiceCommandType {
  startNavigation,
  stopNavigation,
  describeSurroundings,
  readText,
  findItem,
  saveItem,
  detectObjects,
  recognizeCurrency,
  findPerson,
  takeMeTo,
  whereAmI,
  goBack,
  increaseSpeechSpeed,
  decreaseSpeechSpeed,
  startListening,
  stopListening,
  repeat,
  help,
  openSettings,
  stopSpeaking,
  emergency,
  toggleObstacleAlerts,
  switchLanguage,
  toggleTorch,
  aroundMe,
  batteryStatus,
  readBusRoute,
  facingDirection,
  checkTrafficLight,
  saveFavoritePlace,
  enrollFriend,
  whoIsHere,
  none,
  unknown,
}

/// A parsed voice command with an optional free-text [argument].
class VoiceCommand {
  final VoiceCommandType type;
  final String rawText;
  final String? argument;

  const VoiceCommand({
    required this.type,
    required this.rawText,
    this.argument,
  });

  @override
  String toString() => 'VoiceCommand(type: $type, rawText: "$rawText", arg: "$argument")';
}
