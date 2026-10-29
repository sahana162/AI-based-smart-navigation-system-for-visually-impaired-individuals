import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../models/navigation_step.dart';
import 'storage_service.dart';
import 'tts_service.dart';

enum NavigationStatus {
  idle,
  requestingPermission,
  geocoding,
  routing,
  navigating,
  arrived,
  error,
}

/// Service providing real GPS-based pedestrian navigation, geocoding, turn-by-turn guidance,
/// route deviation detection, and walking instructions for visually impaired users.
class PedestrianNavigationService extends ChangeNotifier {
  final TtsService ttsService;
  final StorageService? storageService;

  NavigationStatus _status = NavigationStatus.idle;
  String _statusMessage = 'Navigation idle.';
  PedestrianRoute? _currentRoute;
  int _currentStepIndex = 0;
  Position? _lastKnownPosition;
  StreamSubscription<Position>? _positionStreamSub;
  DateTime? _lastInstructionAnnouncementTime;
  int _lastAnnouncedStepIndex = -1;
  double _smoothedHeading = -1.0;

  PedestrianNavigationService({
    required this.ttsService,
    this.storageService,
  });

  /// Applies circular exponential moving average (EMA) to prevent compass jitter and 0°/360° jump.
  double updateSmoothedHeading(double rawHeading) {
    if (rawHeading < 0) return _smoothedHeading;
    if (_smoothedHeading < 0) {
      _smoothedHeading = rawHeading;
      return _smoothedHeading;
    }
    final double diff = (rawHeading - _smoothedHeading + 180) % 360 - 180;
    _smoothedHeading = (_smoothedHeading + diff * 0.35 + 360) % 360;
    return _smoothedHeading;
  }

  NavigationStatus get status => _status;
  String get statusMessage => _statusMessage;
  PedestrianRoute? get currentRoute => _currentRoute;
  int get currentStepIndex => _currentStepIndex;
  Position? get lastKnownPosition => _lastKnownPosition;
  bool get isNavigating => _status == NavigationStatus.navigating;

  PedestrianStep? get currentStep {
    if (_currentRoute == null || _currentRoute!.steps.isEmpty) return null;
    if (_currentStepIndex >= _currentRoute!.steps.length) return null;
    return _currentRoute!.steps[_currentStepIndex];
  }

  // ── 1. Permission & Location Availability ───────────────────────────────────

  /// Verifies location services and requests permissions with spoken explanation.
  Future<bool> ensureLocationPermission() async {
    final isKn = ttsService.isKannada;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _status = NavigationStatus.error;
      _statusMessage = isKn ? 'ಜಿಪಿಎಸ್ ಸೇವೆಯನ್ನು ಆಫ್ ಮಾಡಲಾಗಿದೆ.' : 'GPS is disabled on this device.';
      notifyListeners();
      await ttsService.speak(
        isKn
            ? 'ಈ ಸಾಧನದಲ್ಲಿ ಜಿಪಿಎಸ್ ಸ್ಥಳ ಆಫ್ ಆಗಿದೆ. ದಯವಿಟ್ಟು ಸೆಟ್ಟಿಂಗ್ಸ್‌ನಲ್ಲಿ ಸ್ಥಳ ಸೇವೆಯನ್ನು ಆನ್ ಮಾಡಿ.'
            : 'GPS location is turned off on this device. Please enable location services in device settings.',
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await ttsService.speak(
        isKn
            ? 'ಸ್ಮಾರ್ಟ್ ನ್ಯಾವಿಗೇಷನ್ ನಿಮಗೆ ದಾರಿ ತೋರಿಸಲು ಜಿಪಿಎಸ್ ಅನುಮತಿ ಅಗತ್ಯವಿದೆ. ದಯವಿಟ್ಟು ಅನುಮತಿ ನೀಡಿ.'
            : 'Smart Navigation needs GPS access to guide you along your walking route. Please grant location permission.',
      );
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _status = NavigationStatus.error;
        _statusMessage = isKn ? 'ಜಿಪಿಎಸ್ ಅನುಮತಿ ನಿರಾಕರಿಸಲಾಗಿದೆ.' : 'Location permission denied.';
        notifyListeners();
        await ttsService.speak(
          isKn
              ? 'ಜಿಪಿಎಸ್ ಅನುಮತಿ ನಿರಾಕರಿಸಲಾಗಿದೆ. ಜಿಪಿಎಸ್ ಇಲ್ಲದೆ ನಡಿಗೆ ನ್ಯಾವಿಗೇಷನ್ ಸಾಧ್ಯವಿಲ್ಲ.'
              : 'Location permission was denied. Pedestrian navigation cannot proceed without GPS access.',
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _status = NavigationStatus.error;
      _statusMessage = isKn ? 'ಜಿಪಿಎಸ್ ಅನುಮತಿ ಶಾಶ್ವತವಾಗಿ ನಿರಾಕರಿಸಲಾಗಿದೆ.' : 'Location permission permanently denied.';
      notifyListeners();
      await ttsService.speak(
        isKn
            ? 'ಜಿಪಿಎಸ್ ಅನುಮತಿಯನ್ನು ಶಾಶ್ವತವಾಗಿ ನಿರಾಕರಿಸಲಾಗಿದೆ. ದಯವಿಟ್ಟು ಅಪ್ಲಿಕೇಶನ್ ಸೆಟ್ಟಿಂಗ್ಸ್‌ನಲ್ಲಿ ಅನುಮತಿ ನೀಡಿ.'
            : 'Location permission is permanently denied. Please enable location in application settings.',
      );
      return false;
    }

    return true;
  }

  /// Obtains the device's actual GPS position.
  Future<Position?> getCurrentPosition() async {
    final ok = await ensureLocationPermission();
    if (!ok) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _lastKnownPosition = pos;
      notifyListeners();
      return pos;
    } catch (e) {
      debugPrint('Error getting GPS position: $e');
      return null;
    }
  }

  // ── 2. "Where Am I?" Real Geocoding & Emergency Location ───────────────────

  /// Resolves device GPS coordinates and reverse-geocodes to the nearest street address.
  Future<Map<String, dynamic>?> resolveCurrentLocation() async {
    final pos = await getCurrentPosition();
    if (pos == null) return null;

    String road = '';
    String suburb = '';
    String displayName = '';

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'BlindNavigationApp/1.0 (accessibility research; contact: dev@blindnavigation.org)',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        displayName = (data['display_name'] ?? '').toString();
        road = (data['address']?['road'] ?? '').toString();
        suburb = (data['address']?['suburb'] ?? data['address']?['city'] ?? '').toString();
      }
    } catch (e) {
      debugPrint('PedestrianNavigationService reverse-geocode exception: $e');
    }

    return {
      'position': pos,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy': pos.accuracy,
      'road': road,
      'suburb': suburb,
      'displayName': displayName,
    };
  }

  /// Speaks the user's current GPS location and resolved address aloud, with emergency support.
  Future<Map<String, dynamic>?> announceCurrentLocation({bool isEmergency = false}) async {
    final isKn = ttsService.isKannada;
    if (isEmergency) {
      await ttsService.speak(
        isKn ? 'ತುರ್ತು ಜಿಪಿಎಸ್ ಸ್ಥಳವನ್ನು ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...' : 'Acquiring emergency GPS location...',
      );
    } else {
      await ttsService.speak(
        isKn ? 'ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳವನ್ನು ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...' : 'Checking your current GPS location...',
      );
    }

    final loc = await resolveCurrentLocation();
    if (loc == null) {
      final failMsg = isKn
          ? 'ಜಿಪಿಎಸ್ ಸಿಗ್ನಲ್ ಸಿಗುತ್ತಿಲ್ಲ. ದಯವಿಟ್ಟು ಮುಕ್ತ ಆಕಾಶವಿರುವ ಜಾಗಕ್ಕೆ ಬನ್ನಿ.'
          : 'Unable to obtain GPS fix. Please ensure you are outdoors with a clear view of the sky.';
      await ttsService.speak(failMsg);
      return null;
    }

    final double lat = loc['latitude'] as double;
    final double lng = loc['longitude'] as double;
    final double acc = loc['accuracy'] as double;
    final String road = loc['road'] as String;
    final String suburb = loc['suburb'] as String;
    final String displayName = loc['displayName'] as String;

    final String addressDesc = road.isNotEmpty
        ? (suburb.isNotEmpty ? '$road, $suburb' : road)
        : (displayName.isNotEmpty ? displayName : '');

    if (isEmergency) {
      if (isKn) {
        final locDetail = addressDesc.isNotEmpty ? 'ಹತ್ತಿರದ ವಿಳಾಸ: $addressDesc.' : '';
        await ttsService.speak(
          'ತುರ್ತು ಎಚ್ಚರಿಕೆ! ನಿಮ್ಮ ಜಿಪಿಎಸ್ ಸ್ಥಳ: ಅಕ್ಷಾಂಶ ${lat.toStringAsFixed(4)}, ರೇಖಾಂಶ ${lng.toStringAsFixed(4)}. $locDetail ತುರ್ತು ಸಹಾಯಕ್ಕಾಗಿ ತಕ್ಷಣ 112 ಕರೆ ಮಾಡಿ.',
        );
      } else {
        final locDetail = addressDesc.isNotEmpty ? 'Near $addressDesc.' : '';
        await ttsService.speak(
          'Emergency alert! Your GPS coordinates are latitude ${lat.toStringAsFixed(4)}, longitude ${lng.toStringAsFixed(4)}. $locDetail Call 112 immediately.',
        );
      }
    } else {
      if (isKn) {
        if (addressDesc.isNotEmpty) {
          await ttsService.speak('ನೀವು $addressDesc ಹತ್ತಿರ ಇದ್ದೀರಿ. ಜಿಪಿಎಸ್ ನಿಖರತೆ ${acc.round()} ಮೀಟರ್.');
        } else {
          await ttsService.speak('ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳ: ಅಕ್ಷಾಂಶ ${lat.toStringAsFixed(4)}, ರೇಖಾಂಶ ${lng.toStringAsFixed(4)}.');
        }
      } else {
        if (addressDesc.isNotEmpty) {
          await ttsService.speak('You are near $addressDesc. GPS accuracy is within ${acc.round()} meters.');
        } else {
          await ttsService.speak('Current coordinates are latitude ${lat.toStringAsFixed(4)}, longitude ${lng.toStringAsFixed(4)}.');
        }
      }
    }

    return loc;
  }

  /// Speaks device cardinal heading and orientation (e.g., North, North-East) for blind pedestrian orientation.
  Future<void> announceFacingDirection() async {
    final hasPerm = await ensureLocationPermission();
    if (!hasPerm) return;

    Position? pos = _lastKnownPosition;
    pos ??= await getCurrentPosition();

    final isKn = ttsService.isKannada;
    final smoothed = updateSmoothedHeading(pos?.heading ?? -1.0);
    if (pos == null || (pos.heading < 0 && smoothed < 0)) {
      final msg = isKn
          ? 'ದಿಕ್ಸೂಚಿ ದೃಷ್ಟಿಕೋನ ಇನ್ನೂ ಲಭ್ಯವಿಲ್ಲ. ದಿಕ್ಸೂಚಿ ಮಾಪನಾಂಕ ನಿರ್ಣಯಕ್ಕಾಗಿ ಕೆಲವು ಹೆಜ್ಜೆಗಳನ್ನು ಮುಂದಿಡಿ.'
          : 'Compass orientation is not yet calibrated. Take a couple of steps forward to establish heading.';
      await ttsService.speak(msg);
      return;
    }

    final headingDeg = (smoothed % 360 + 360) % 360;
    final int degrees = headingDeg.round();

    final String cardinalEn;
    final String cardinalKn;
    if (headingDeg >= 337.5 || headingDeg < 22.5) {
      cardinalEn = 'North';
      cardinalKn = 'ಉತ್ತರ';
    } else if (headingDeg >= 22.5 && headingDeg < 67.5) {
      cardinalEn = 'North-East';
      cardinalKn = 'ಈಶಾನ್ಯ';
    } else if (headingDeg >= 67.5 && headingDeg < 112.5) {
      cardinalEn = 'East';
      cardinalKn = 'ಪೂರ್ವ';
    } else if (headingDeg >= 112.5 && headingDeg < 157.5) {
      cardinalEn = 'South-East';
      cardinalKn = 'ಆಗ್ನೇಯ';
    } else if (headingDeg >= 157.5 && headingDeg < 202.5) {
      cardinalEn = 'South';
      cardinalKn = 'ದಕ್ಷಿಣ';
    } else if (headingDeg >= 202.5 && headingDeg < 247.5) {
      cardinalEn = 'South-West';
      cardinalKn = 'ನೈಋತ್ಯ';
    } else if (headingDeg >= 247.5 && headingDeg < 292.5) {
      cardinalEn = 'West';
      cardinalKn = 'ಪಶ್ಚಿಮ';
    } else {
      cardinalEn = 'North-West';
      cardinalKn = 'ವಾಯುವ್ಯ';
    }

    final speech = isKn
        ? 'ನೀವು $cardinalKn ($degrees ಡಿಗ್ರಿ) ದಿಕ್ಕಿಗೆ ಮುಖ ಮಾಡಿದ್ದೀರಿ.'
        : 'You are facing $cardinalEn, $degrees degrees.';
    await ttsService.speak(speech);
  }

  /// Discovers points of interest (bus stops, crossings, pharmacies, ATMs, shops) within [radiusMeters]
  /// and returns them sorted by ascending distance, with clock-face directions.
  Future<List<Map<String, dynamic>>> exploreNearbyAmenities({int radiusMeters = 150}) async {
    final pos = await getCurrentPosition();
    if (pos == null) return [];

    try {
      final query = '''
[out:json][timeout:8];
(
  node["highway"~"bus_stop|crossing"](around:$radiusMeters,${pos.latitude},${pos.longitude});
  node["amenity"~"pharmacy|hospital|clinic|bank|atm|bus_station|restaurant|cafe|toilets"](around:$radiusMeters,${pos.latitude},${pos.longitude});
  node["shop"~"supermarket|convenience|bakery|chemist"](around:$radiusMeters,${pos.latitude},${pos.longitude});
);
out body 10;
''';
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'BlindNavigationApp/1.0 (accessibility research; contact: dev@blindnavigation.org)',
        },
        body: 'data=${Uri.encodeComponent(query)}',
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List? ?? [];
        final List<Map<String, dynamic>> results = [];

        for (final el in elements) {
          final double? elLat = (el['lat'] as num?)?.toDouble();
          final double? elLon = (el['lon'] as num?)?.toDouble();
          if (elLat == null || elLon == null) continue;

          final tags = el['tags'] as Map<String, dynamic>? ?? {};
          final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, elLat, elLon).round();
          if (distance > radiusMeters) continue;

          final bearing = Geolocator.bearingBetween(pos.latitude, pos.longitude, elLat, elLon);
          // Calculate clock position (1 to 12)
          double relBearing = (pos.heading >= 0) ? (bearing - pos.heading) : bearing;
          relBearing = (relBearing % 360 + 360) % 360;
          int clockHour = ((relBearing + 15) ~/ 30) % 12;
          if (clockHour == 0) clockHour = 12;

          String typeEn = 'Place of interest';
          String typeKn = 'ಸ್ಥಳ';

          if (tags['highway'] == 'bus_stop' || tags['amenity'] == 'bus_station') {
            typeEn = 'Bus stop';
            typeKn = 'ಬಸ್ ನಿಲ್ದಾಣ';
          } else if (tags['highway'] == 'crossing') {
            typeEn = 'Pedestrian crossing';
            typeKn = 'ಪಾದಚಾರಿ ಕ್ರಾಸಿಂಗ್';
          } else if (tags['amenity'] == 'pharmacy' || tags['shop'] == 'chemist') {
            typeEn = 'Pharmacy';
            typeKn = 'ಫಾರ್ಮಸಿ';
          } else if (tags['amenity'] == 'hospital' || tags['amenity'] == 'clinic') {
            typeEn = 'Clinic';
            typeKn = 'ಆಸ್ಪತ್ರೆ';
          } else if (tags['amenity'] == 'atm') {
            typeEn = 'ATM';
            typeKn = 'ಎಟಿಎಂ';
          } else if (tags['amenity'] == 'bank') {
            typeEn = 'Bank';
            typeKn = 'ಬ್ಯಾಂಕ್';
          } else if (tags['amenity'] == 'restaurant' || tags['amenity'] == 'cafe') {
            typeEn = 'Restaurant';
            typeKn = 'ಹೋಟೆಲ್';
          } else if (tags['amenity'] == 'toilets') {
            typeEn = 'Restroom';
            typeKn = 'ಶೌಚಾಲಯ';
          } else if (tags['shop'] == 'supermarket' || tags['shop'] == 'convenience') {
            typeEn = 'Grocery store';
            typeKn = 'ಕಿರಾಣಿ ಅಂಗಡಿ';
          }

          final String name = (tags['name'] ?? '').toString().trim();

          results.add({
            'name': name,
            'typeEn': typeEn,
            'typeKn': typeKn,
            'distance': distance,
            'clockHour': clockHour,
            'latitude': elLat,
            'longitude': elLon,
          });
        }

        results.sort((a, b) => (a['distance'] as int).compareTo(b['distance'] as int));
        return results.take(5).toList();
      }
    } catch (e) {
      debugPrint('PedestrianNavigationService Overpass exploration exception: $e');
    }
    return [];
  }

  /// Speaks nearby points of interest aloud in natural clock-face bearings.
  Future<void> announceNearbyAmenities() async {
    final isKn = ttsService.isKannada;
    await ttsService.speak(
      isKn ? 'ನಿಮ್ಮ ಸುತ್ತಲಿನ ಸ್ಥಳಗಳನ್ನು ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...' : 'Scanning amenities around you...',
    );

    final amenities = await exploreNearbyAmenities(radiusMeters: 150);
    if (amenities.isEmpty) {
      final loc = await resolveCurrentLocation();
      final road = loc?['road'] as String? ?? '';
      if (isKn) {
        final roadDetail = road.isNotEmpty ? '$road ರಸ್ತೆಯ ಹತ್ತಿರ ಇದ್ದೀರಿ.' : '';
        await ttsService.speak(
          '150 ಮೀಟರ್ ವ್ಯಾಪ್ತಿಯಲ್ಲಿ ಯಾವುದೇ ಪ್ರಮುಖ ಸ್ಥಳಗಳು ಕಂಡುಬಂದಿಲ್ಲ. $roadDetail',
        );
      } else {
        final roadDetail = road.isNotEmpty ? 'You are near $road.' : '';
        await ttsService.speak(
          'No specific landmarks found within 150 meters. $roadDetail',
        );
      }
      return;
    }

    final StringBuffer sb = StringBuffer();
    if (isKn) {
      sb.write('150 ಮೀಟರ್ ವ್ಯಾಪ್ತಿಯಲ್ಲಿ ${amenities.length} ಸ್ಥಳಗಳು ಕಂಡುಬಂದಿವೆ: ');
      for (int i = 0; i < amenities.length; i++) {
        final item = amenities[i];
        final name = (item['name'] as String).isNotEmpty ? item['name'] : item['typeKn'];
        final dist = item['distance'];
        final clock = item['clockHour'];
        sb.write('$dist ಮೀಟರ್ $clock ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ $name. ');
      }
    } else {
      sb.write('Found ${amenities.length} places within 150 meters: ');
      for (int i = 0; i < amenities.length; i++) {
        final item = amenities[i];
        final name = (item['name'] as String).isNotEmpty ? item['name'] : item['typeEn'];
        final dist = item['distance'];
        final clock = item['clockHour'];
        final clockStr = clock == 12 ? 'straight ahead' : 'at your $clock o\'clock';
        sb.write('$name, $dist meters $clockStr. ');
      }
    }

    await ttsService.speak(sb.toString().trim());
  }

  // ── 3. Destination Geocoding & Routing ─────────────────────────────────────

  /// Resolves spoken destination to coordinates, obtains pedestrian route, and starts guidance.
  Future<bool> startNavigationToDestination(String destinationQuery) async {
    final cleanDest = destinationQuery.trim();
    final isKn = ttsService.isKannada;
    if (cleanDest.isEmpty) {
      await ttsService.speak(isKn ? 'ದಯವಿಟ್ಟು ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಿಳಿಸಿ.' : 'Please specify a destination.');
      return false;
    }

    final hasPerm = await ensureLocationPermission();
    if (!hasPerm) return false;

    _status = NavigationStatus.geocoding;
    _statusMessage = isKn ? '$cleanDest ಹುಡುಕಲಾಗುತ್ತಿದೆ...' : 'Searching for $cleanDest...';
    notifyListeners();
    await ttsService.speak(
      isKn ? '$cleanDest ಗೆ ನಡಿಗೆ ಮಾರ್ಗ ಹುಡುಕಲಾಗುತ್ತಿದೆ.' : 'Searching for pedestrian route to $cleanDest.',
    );

    // 1. Resolve destination via favorite places first, cache, or Nominatim OpenStreetMap
    Map<String, dynamic>? geocodeResult;
    if (storageService != null) {
      final fav = storageService!.getFavoritePlace(cleanDest);
      if (fav != null) {
        geocodeResult = {
          'lat': fav['lat'],
          'lon': fav['lon'],
          'display_name': fav['name'] ?? fav['address'],
        };
      } else {
        final cached = storageService!.getCachedDestination(cleanDest);
        if (cached != null) {
          geocodeResult = cached;
        }
      }
    }

    bool networkError = false;
    try {
      final geocodeUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanDest)}&format=json&limit=1&addressdetails=1',
      );
      final res = await http.get(geocodeUrl, headers: {
        'User-Agent': 'BlindNavigationApp/1.0 (accessibility research; contact: dev@blindnavigation.org)',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          geocodeResult = list.first as Map<String, dynamic>;
          // Cache successful geocoding result
          if (storageService != null) {
            storageService!.cacheGeocodedDestination(
              query: cleanDest,
              lat: double.parse(geocodeResult['lat'].toString()),
              lng: double.parse(geocodeResult['lon'].toString()),
              displayName: geocodeResult['display_name']?.toString() ?? cleanDest,
            );
          }
        }
      }
    } catch (e) {
      networkError = true;
      debugPrint('Geocoding network error: $e');
    }

    if (geocodeResult == null) {
      _status = NavigationStatus.error;
      _statusMessage = isKn ? 'ಸ್ಥಳ ಕಂಡುಬಂದಿಲ್ಲ: $cleanDest' : 'Destination not found: $cleanDest';
      notifyListeners();

      if (networkError) {
        final offlineMsg = isKn
            ? 'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿದೆ. ಉಳಿಸಿದ ಸ್ಥಳಗಳಿಗೆ ಮಾರ್ಗದರ್ಶನ ಲಭ್ಯವಿದೆ ಅಥವಾ ದಿಕ್ಸೂಚಿ ಬಳಸಿ ಮಾರ್ಗದರ್ಶನ ಮಾಡಬಹುದು.'
            : 'Operating offline. Routing is available for your saved favorite places, or I can guide you using compass bearing.';
        await ttsService.speak(offlineMsg);
      } else {
        await ttsService.speak(
          isKn
              ? '$cleanDest ಗೆ ಸ್ಥಳ ಕಂಡುಬಂದಿಲ್ಲ. ದಯವಿಟ್ಟು ಸ್ಪಷ್ಟವಾದ ವಿಳಾಸ ಅಥವಾ ಹೆಗ್ಗುರುತನ್ನು ತಿಳಿಸಿ.'
              : 'Could not find location for $cleanDest. Please try a more specific address or landmark.',
        );
      }
      return false;
    }

    final destLat = double.parse(geocodeResult['lat'].toString());
    final destLng = double.parse(geocodeResult['lon'].toString());
    final destName = geocodeResult['display_name']?.toString().split(',').first ?? cleanDest;

    // 2. Obtain device position
    _status = NavigationStatus.routing;
    _statusMessage = isKn ? 'ಜಿಪಿಎಸ್ ಸಿಗ್ನಲ್ ಪಡೆಯಲಾಗುತ್ತಿದೆ...' : 'Acquiring GPS fix...';
    notifyListeners();

    final currentPos = await getCurrentPosition();
    if (currentPos == null) {
      _status = NavigationStatus.error;
      _statusMessage = isKn ? 'ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳ ಸಿಗುತ್ತಿಲ್ಲ.' : 'Unable to get current GPS location.';
      notifyListeners();
      await ttsService.speak(
        isKn
            ? 'ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳ ಸಿಗುತ್ತಿಲ್ಲ. ದಯವಿಟ್ಟು ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.'
            : 'Unable to obtain current GPS location. Please check your signal and try again.',
      );
      return false;
    }

    // 3. Fetch Real Pedestrian Route from OSRM Walking (foot) Router
    _statusMessage = isKn ? 'ನಡಿಗೆ ಮಾರ್ಗ ಲೆಕ್ಕಹಾಕಲಾಗುತ್ತಿದೆ...' : 'Calculating pedestrian walking route...';
    notifyListeners();

    final route = await _fetchPedestrianRoute(
      startLat: currentPos.latitude,
      startLng: currentPos.longitude,
      destLat: destLat,
      destLng: destLng,
      destName: destName,
    );

    // Failover: If walking router fails (server down / offline / no footpath), fallback to Direct Compass Guidance Mode!
    if (route == null || route.steps.isEmpty) {
      final directDistance = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        destLat,
        destLng,
      );
      final initialBearing = Geolocator.bearingBetween(
        currentPos.latitude,
        currentPos.longitude,
        destLat,
        destLng,
      );
      double? relativeBearing;
      if (currentPos.heading >= 0) {
        relativeBearing = (initialBearing - currentPos.heading + 360) % 360;
      }

      final directRoute = PedestrianRoute(
        destinationName: destName,
        destinationLat: destLat,
        destinationLng: destLng,
        totalDistanceMeters: directDistance,
        totalDurationSeconds: directDistance / 1.1, // avg walking speed ~1.1 m/s
        isDirectCompassMode: true,
        steps: [
          PedestrianStep(
            instruction: 'Head towards $destName',
            streetName: destName,
            maneuverType: 'depart',
            maneuverModifier: 'straight',
            distanceMeters: directDistance,
            durationSeconds: directDistance / 1.1,
            waypointLat: destLat,
            waypointLng: destLng,
          ),
        ],
        polylineCoordinates: [
          [currentPos.latitude, currentPos.longitude],
          [destLat, destLng],
        ],
      );

      _currentRoute = directRoute;
      _currentStepIndex = 0;
      _lastAnnouncedStepIndex = -1;
      _status = NavigationStatus.navigating;
      notifyListeners();

      HapticFeedback.mediumImpact();

      final distanceM = directDistance.round();
      final clockDir = PedestrianStep.formatClockDirection(relativeBearing, isKannada: isKn);
      await ttsService.speak(
        isKn
            ? '$destName ಗೆ ನೇರ ದಿಕ್ಸೂಚಿ ಮಾರ್ಗದರ್ಶನ ಸಕ್ರಿಯವಾಗಿದೆ. ಒಟ್ಟು ದೂರ ಸುಮಾರು $distanceM ಮೀಟರ್$clockDir. ಯಾವಾಗಲೂ ನಿಮ್ಮ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಬಳಸಿ ಎಚ್ಚರಿಕೆಯಿಂದ ಮುನ್ನಡೆಯಿರಿ.'
            : 'Direct compass guidance active to $destName. Distance is approximately $distanceM meters$clockDir. Always use your cane or mobility aid and walk with caution.',
      );

      _startLocationTracking();
      return true;
    }

    _currentRoute = route;
    _currentStepIndex = 0;
    _lastAnnouncedStepIndex = -1;
    _status = NavigationStatus.navigating;
    notifyListeners();

    HapticFeedback.mediumImpact();

    final distanceKm = (route.totalDistanceMeters / 1000).toStringAsFixed(1);
    final durationMins = (route.totalDurationSeconds / 60).round();
    await ttsService.speak(
      isKn
          ? '$destName ಗೆ ನಡಿಗೆ ಮಾರ್ಗ ಸಿಕ್ಕಿದೆ. ಒಟ್ಟು ದೂರ $distanceKm ಕಿಲೋಮೀಟರ್, ಸುಮಾರು $durationMins ನಿಮಿಷಗಳ ನಡಿಗೆ. ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭವಾಗುತ್ತಿದೆ. ಯಾವಾಗಲೂ ನಿಮ್ಮ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಬಳಸಿ ಎಚ್ಚರಿಕೆಯಿಂದ ಮುನ್ನಡೆಯಿರಿ.'
          : 'Walking route to $destName found. Total distance is $distanceKm kilometers, approximately $durationMins minutes walk. Starting navigation. Always use your cane or mobility aid and remain cautious.',
    );

    _startLocationTracking();
    _announceNextInstruction();
    return true;
  }

  Future<PedestrianRoute?> _fetchPedestrianRoute({
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
    required String destName,
  }) async {
    try {
      final routeUrl = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/$startLng,$startLat;$destLng,$destLat?overview=full&steps=true&geometries=geojson',
      );
      final res = await http.get(routeUrl, headers: {
        'User-Agent': 'BlindNavigationApp/1.0 (accessibility research; contact: dev@blindnavigation.org)',
      }).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) return null;

      final routeData = data['routes'][0];
      final totalDist = (routeData['distance'] as num).toDouble();
      final totalDuration = (routeData['duration'] as num).toDouble();

      final List<PedestrianStep> steps = [];
      final legs = routeData['legs'] as List;
      for (final leg in legs) {
        final stepList = leg['steps'] as List;
        for (final s in stepList) {
          final maneuver = s['maneuver'] ?? {};
          final location = maneuver['location'] as List; // [lng, lat]
          steps.add(PedestrianStep(
            instruction: s['name'] != null && (s['name'] as String).isNotEmpty
                ? 'Continue onto ${s['name']}'
                : 'Continue',
            streetName: (s['name'] ?? '').toString(),
            maneuverType: (maneuver['type'] ?? 'continue').toString(),
            maneuverModifier: (maneuver['modifier'] ?? '').toString(),
            distanceMeters: (s['distance'] as num).toDouble(),
            durationSeconds: (s['duration'] as num).toDouble(),
            waypointLng: (location[0] as num).toDouble(),
            waypointLat: (location[1] as num).toDouble(),
          ));
        }
      }

      final coords = (routeData['geometry']['coordinates'] as List)
          .map<List<double>>((pt) => [(pt[1] as num).toDouble(), (pt[0] as num).toDouble()])
          .toList();

      return PedestrianRoute(
        destinationName: destName,
        destinationLat: destLat,
        destinationLng: destLng,
        totalDistanceMeters: totalDist,
        totalDurationSeconds: totalDuration,
        steps: steps,
        polylineCoordinates: coords,
      );
    } catch (e) {
      debugPrint('Error fetching pedestrian route: $e');
      return null;
    }
  }

  // ── 4. Live Tracking & Turn-by-Turn Guidance ────────────────────────────────

  void _startLocationTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // Update every 3 meters
      ),
    ).listen(
      _handlePositionUpdate,
      onError: (err) {
        debugPrint('Location stream error: $err');
      },
    );
  }

  Future<void> _handlePositionUpdate(Position position) async {
    _lastKnownPosition = position;
    if (_status != NavigationStatus.navigating || _currentRoute == null) return;

    // Filter out low-accuracy GPS multipath spikes (> 35m uncertainty radius)
    if (position.accuracy > 35.0) {
      debugPrint('[PedestrianNavigation] GPS multipath jitter suppressed (accuracy: ${position.accuracy}m)');
      return;
    }

    final route = _currentRoute!;
    final destDist = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      route.destinationLat,
      route.destinationLng,
    );

    // 1. Arrival Check
    if (destDist <= 15) {
      _status = NavigationStatus.arrived;
      final isKn = ttsService.isKannada;
      _statusMessage = isKn ? '${route.destinationName} ತಲುಪಿದ್ದೀರಿ.' : 'Arrived at ${route.destinationName}.';
      notifyListeners();
      HapticFeedback.heavyImpact();
      await ttsService.speak(
        isKn
            ? 'ನೀವು ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವಾದ ${route.destinationName} ತಲುಪಿದ್ದೀರಿ. ಪಾದಚಾರಿ ನ್ಯಾವಿಗೇಷನ್ ಪೂರ್ಣಗೊಂಡಿದೆ.'
            : 'You have arrived at your destination, ${route.destinationName}. Pedestrian navigation has completed.',
      );
      stopNavigation();
      return;
    }

    // Direct Compass Guidance Mode Handling
    if (route.isDirectCompassMode) {
      final now = DateTime.now();
      if (_lastInstructionAnnouncementTime == null ||
          now.difference(_lastInstructionAnnouncementTime!).inSeconds >= 18) {
        _lastInstructionAnnouncementTime = now;
        final bearingToDest = Geolocator.bearingBetween(
          position.latitude,
          position.longitude,
          route.destinationLat,
          route.destinationLng,
        );
        double? relativeBearing;
        if (position.heading >= 0) {
          relativeBearing = (bearingToDest - position.heading + 360) % 360;
        }
        final clockDir = PedestrianStep.formatClockDirection(relativeBearing, isKannada: ttsService.isKannada);
        final distRound = destDist.round();
        final guidance = ttsService.isKannada
            ? '${route.destinationName}: ಸುಮಾರು $distRound ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ$clockDir.'
            : '${route.destinationName} is approximately $distRound meters away$clockDir.';
        _statusMessage = guidance;
        notifyListeners();
        await ttsService.speak(guidance);
      }
      return;
    }

    // 2. Step Advancement Check (advance if reached within 12 meters of step waypoint)
    if (_currentStepIndex < route.steps.length) {
      final step = route.steps[_currentStepIndex];
      final distToStep = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        step.waypointLat,
        step.waypointLng,
      );

      // Advance step if reached within 12m
      if (distToStep < 12 && _currentStepIndex < route.steps.length - 1) {
        _currentStepIndex++;
        notifyListeners();
        HapticFeedback.mediumImpact();
        _announceNextInstruction();
        return;
      }

      // 3. True Polyline Off-route Check (deviation > 50 meters from route path)
      final offRouteDistance = _minDistanceToRoute(position, route);
      if (offRouteDistance > 50 && destDist > 50) {
        final now = DateTime.now();
        if (_lastInstructionAnnouncementTime == null ||
            now.difference(_lastInstructionAnnouncementTime!).inSeconds > 30) {
          _lastInstructionAnnouncementTime = now;
          HapticFeedback.vibrate();
          await ttsService.speak(
            ttsService.isKannada
                ? 'ನೀವು ದಾರಿಯಿಂದ ದೂರ ಸರಿದಿರಬಹುದು. ನಡಿಗೆ ಮಾರ್ಗವನ್ನು ಮರುಲೆಕ್ಕಾಚಾರ ಮಾಡಲಾಗುತ್ತಿದೆ.'
                : 'You may have deviated from the path. Recalculating walking route.',
          );
          _recalculateRoute(position);
          return;
        }
      }
    }

    notifyListeners();
  }

  /// Calculates minimum distance in meters between user position and any point on the route polyline.
  double _minDistanceToRoute(Position pos, PedestrianRoute route) {
    if (route.polylineCoordinates.isEmpty) return 0.0;
    double minDistance = double.infinity;
    for (final coord in route.polylineCoordinates) {
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        coord[0],
        coord[1],
      );
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }

  Future<void> _recalculateRoute(Position currentPos) async {
    if (_currentRoute == null) return;
    final freshRoute = await _fetchPedestrianRoute(
      startLat: currentPos.latitude,
      startLng: currentPos.longitude,
      destLat: _currentRoute!.destinationLat,
      destLng: _currentRoute!.destinationLng,
      destName: _currentRoute!.destinationName,
    );

    if (freshRoute != null && freshRoute.steps.isNotEmpty) {
      _currentRoute = freshRoute;
      _currentStepIndex = 0;
      _lastAnnouncedStepIndex = -1;
      notifyListeners();
      await ttsService.speak(ttsService.isKannada ? 'ಮಾರ್ಗವನ್ನು ನವೀಕರಿಸಲಾಗಿದೆ.' : 'Route updated.');
      _announceNextInstruction();
    }
  }

  Future<void> _announceNextInstruction() async {
    if (_currentRoute == null || _currentStepIndex >= _currentRoute!.steps.length) return;
    if (_currentStepIndex == _lastAnnouncedStepIndex) return;

    _lastAnnouncedStepIndex = _currentStepIndex;
    _lastInstructionAnnouncementTime = DateTime.now();

    final step = _currentRoute!.steps[_currentStepIndex];
    playTurnHaptic(step);
    double remaining = step.distanceMeters;
    double? relativeBearing;
    if (_lastKnownPosition != null) {
      remaining = Geolocator.distanceBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        step.waypointLat,
        step.waypointLng,
      );

      final bearingToWaypoint = Geolocator.bearingBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        step.waypointLat,
        step.waypointLng,
      );

      if (_lastKnownPosition!.heading >= 0) {
        relativeBearing = (bearingToWaypoint - _lastKnownPosition!.heading + 360) % 360;
      }
    }

    final speech = step.spokenInstruction(
      remainingMeters: remaining,
      isKannada: ttsService.isKannada,
      relativeBearingDegrees: relativeBearing,
    );
    _statusMessage = speech;
    notifyListeners();
    await ttsService.speak(speech);
  }

  /// Repeats the current navigation turn instruction aloud.
  Future<void> repeatCurrentInstruction() async {
    if (_status != NavigationStatus.navigating || _currentRoute == null) {
      await ttsService.speak(
        ttsService.isKannada ? 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಸ್ತುತ ಸಕ್ರಿಯವಾಗಿಲ್ಲ.' : 'Navigation is not currently active.',
      );
      return;
    }

    final route = _currentRoute!;
    if (route.isDirectCompassMode && _lastKnownPosition != null) {
      final destDist = Geolocator.distanceBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        route.destinationLat,
        route.destinationLng,
      );
      final bearingToDest = Geolocator.bearingBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        route.destinationLat,
        route.destinationLng,
      );
      double? relativeBearing;
      if (_lastKnownPosition!.heading >= 0) {
        relativeBearing = (bearingToDest - _lastKnownPosition!.heading + 360) % 360;
      }
      final clockDir = PedestrianStep.formatClockDirection(relativeBearing, isKannada: ttsService.isKannada);
      final distRound = destDist.round();
      final speech = ttsService.isKannada
          ? 'ನೇರ ದಿಕ್ಸೂಚಿ ಮಾರ್ಗದರ್ಶನ: ${route.destinationName} $distRound ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ$clockDir.'
          : 'Direct compass guidance: ${route.destinationName} is $distRound meters away$clockDir.';
      await ttsService.speak(speech);
      return;
    }

    final step = currentStep;
    if (step == null) {
      await ttsService.speak(
        ttsService.isKannada ? 'ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನಕ್ಕೆ ಮುಂದುವರಿಯಿರಿ.' : 'Proceed to your destination.',
      );
      return;
    }

    double remaining = step.distanceMeters;
    double? relativeBearing;
    if (_lastKnownPosition != null) {
      remaining = Geolocator.distanceBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        step.waypointLat,
        step.waypointLng,
      );

      final bearingToWaypoint = Geolocator.bearingBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        step.waypointLat,
        step.waypointLng,
      );

      if (_lastKnownPosition!.heading >= 0) {
        relativeBearing = (bearingToWaypoint - _lastKnownPosition!.heading + 360) % 360;
      }
    }

    await ttsService.speak(
      step.spokenInstruction(
        remainingMeters: remaining,
        isKannada: ttsService.isKannada,
        relativeBearingDegrees: relativeBearing,
      ),
    );
  }

  /// Emits directional haptic vibration patterns (2 pulses for left, 3 for right, double heavy for arrival).
  Future<void> playTurnHaptic(PedestrianStep step) async {
    if (storageService != null && !storageService!.directionalHapticsEnabled) return;
    if (storageService != null && !storageService!.hapticsEnabled) return;

    final mod = step.maneuverModifier.toLowerCase();
    if (step.maneuverType == 'arrive') {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
    } else if (mod.contains('left')) {
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
    } else if (mod.contains('right')) {
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Saves current GPS coordinates as a favorite bookmark (e.g. Home, Work).
  Future<bool> saveCurrentLocationAsFavorite({
    required String tag,
    String? customName,
  }) async {
    final hasPerm = await ensureLocationPermission();
    if (!hasPerm) return false;

    Position? pos = _lastKnownPosition;
    pos ??= await getCurrentPosition();

    final isKn = ttsService.isKannada;
    if (pos == null) {
      final msg = isKn
          ? 'ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳ ಸಿಗುತ್ತಿಲ್ಲ. ಸ್ಥಳ ಉಳಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
          : 'Unable to acquire GPS fix. Could not save location.';
      await ttsService.speak(msg);
      return false;
    }

    final isHome = tag.toLowerCase() == 'home';
    final defaultDisplayName = isHome
        ? (isKn ? 'ಮನೆ' : 'Home')
        : (isKn ? 'ಕಚೇರಿ' : 'Work');
    final placeName = customName ?? defaultDisplayName;

    String addressDesc = '';
    try {
      final reverseUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&addressdetails=1',
      );
      final res = await http.get(reverseUrl, headers: {
        'User-Agent': 'BlindNavigationApp/1.0 (accessibility research; contact: dev@blindnavigation.org)',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>?;
        final road = addr?['road']?.toString() ?? '';
        final suburb = addr?['suburb']?.toString() ?? '';
        addressDesc = road.isNotEmpty
            ? '$road${suburb.isNotEmpty ? ", $suburb" : ""}'
            : (data['display_name']?.toString().split(',').first ?? '');
      }
    } catch (_) {}

    if (addressDesc.isEmpty) {
      addressDesc = 'Lat ${pos.latitude.toStringAsFixed(4)}, Lon ${pos.longitude.toStringAsFixed(4)}';
    }

    if (storageService != null) {
      await storageService!.saveFavoritePlace(
        name: placeName,
        tag: tag.toLowerCase(),
        lat: pos.latitude,
        lng: pos.longitude,
        address: addressDesc,
      );
    }

    HapticFeedback.mediumImpact();
    final speech = isKn
        ? '$placeName ಉಳಿಸಲಾಗಿದೆ: $addressDesc. ಇನ್ನು ಮುಂದೆ "$placeName ಗೆ ದಾರಿ" ಎಂದು ಹೇಳಬಹುದು.'
        : 'Saved current location as $placeName: $addressDesc. You can now say "Take me to $placeName" anytime.';
    await ttsService.speak(speech);
    return true;
  }

  /// Stops pedestrian navigation, cancels stream, and announces completion.
  void stopNavigation() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _status = NavigationStatus.idle;
    _currentRoute = null;
    _currentStepIndex = 0;
    _statusMessage = 'Navigation stopped.';
    notifyListeners();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }
}
