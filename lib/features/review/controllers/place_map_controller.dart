import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:reviews_app/features/review/models/search_suggestion.dart';
import 'package:reviews_app/localization/app_localizations.dart';
import 'package:reviews_app/utils/popups/loaders.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:reviews_app/features/review/models/place_model.dart';
import 'package:reviews_app/features/review/controllers/place_controller.dart';
import 'package:reviews_app/features/review/controllers/category_controller.dart';
import '../../../data/services/map_service/map_service.dart';
import '../../../utils/constants/colors.dart';
import '../../../utils/constants/enums.dart';
import '../../../utils/constants/marker_icons.dart';
import '../../../utils/constants/map_styles.dart';
import '../../../utils/logging/logger.dart';
import '../../personalization/models/address_model.dart';
import '../models/category_model.dart';
import '../models/google_search_suggestions.dart';
import '../models/recent_search.dart';
import '../models/directions_model.dart';
import '../models/search_filter_model.dart';
import '../../../data/services/map_service/directions_service/directions_service.dart';

class PlacesMapController extends GetxController {
  static PlacesMapController get instance => Get.find();

  // --- CORE MAP VARIABLES ---
  final currentLocation = Rx<LocationData?>(null);
  final pickedLocation = Rx<LatLng?>(null);
  final locationName = 'Getting location...'.obs;
  final markers = <Marker>{}.obs;
  final polylines = <Polyline>{}.obs;
  final isLoading = false.obs;

  // --- DIRECTIONS & ROUTING ---
  final Rx<DirectionsModel?> currentDirections = Rx<DirectionsModel?>(null);
  final showDirections = false.obs;
  final isLoadingDirections = false.obs;
  final selectedRouteIndex = 0.obs;

  // --- PLACES INTEGRATION ---
  final RxList<PlaceModel> displayedPlaces = <PlaceModel>[].obs;
  final Rx<PlaceModel?> selectedPlace = Rx<PlaceModel?>(null);
  PlaceModel? initialPlace; // Place to highlight when map opens
  final RxString selectedCategoryId = ''.obs;
  final RxList<PlaceModel> nearbyPlaces = <PlaceModel>[].obs;
  final RxDouble searchRadius = 5000.0.obs; // 5km default

  // --- ENHANCED SEARCH & UI ---
  final TextEditingController searchController = TextEditingController();
  final searchQuery = ''.obs;
  final searchSuggestions = <SearchSuggestion>[].obs;
  final recentSearches = <RecentSearch>[].obs;
  final isSearching = false.obs;
  final showLocationDetails = false.obs;
  final showBottomSheet = false.obs;

  // --- MAP STYLING & TYPE ---
  final currentMapType = MapType.normal.obs;
  final enabledMapDetails = <MapDetail>[].obs;
  // final isDarkMode =
  //     false.obs; // Map Styles (Reactive for direct widget binding)
  // final RxnString currentMapStyle = RxnString();

  // --- PREMIUM FEATURES ---
  final Rx<LatLng?> currentMapCenter = Rx<LatLng?>(null);
  final RxDouble distanceToSelectedPlace = 0.0.obs;
  final RxDouble currentZoomLevel = 15.0.obs;

  // --- SEARCH FILTERS ---
  final Rx<SearchFilterModel> searchFilters = Rx<SearchFilterModel>(
    SearchFilterModel.empty(),
  );
  final RxList<PlaceModel> filteredPlaces = <PlaceModel>[].obs;

  // --- VOICE SEARCH ---
  final stt.SpeechToText speech = stt.SpeechToText();
  final isListening = false.obs;
  final speechText = ''.obs;

  // --- TECHNICAL ---
  StreamSubscription<LocationData>? _locationSubscription;
  final mapControllerCompleter = Completer<GoogleMapController>();
  GoogleMapController? googleMapController;
  Timer? _searchDebounceTimer;
  bool _isInitialMapSetupComplete = false;

  // --- GETX CONTROLLERS ---
  final PlaceController placeController = Get.find();
  final CategoryController categoryController = Get.find();

  @override
  void onInit() {
    super.onInit();
    // Initialize map style based on current theme BEFORE map is created
    // _initializeMapStyle();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    isLoading.value = true;

    try {
      await _initializeSpeech();
      getCurrentLocation();
      _loadRecentSearches();
      _loadPlaces();

      // Small delay to ensure smooth UX
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      AppLoggerHelper.error('App initialization error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      await speech.initialize();
    } catch (e) {
      AppLoggerHelper.error('Speech initialization error: $e');
    }
  }

  // --- PLACES INTEGRATION METHODS ---
  void _loadPlaces() {
    try {
      AppLoggerHelper.info('Loading places from PlaceController...');

      // Use places from PlaceController
      final availablePlaces = placeController.places;
      AppLoggerHelper.info('Total places loaded: ${availablePlaces.length}');

      // Log places with their categories for debugging
      for (final place in availablePlaces.take(5)) {
        AppLoggerHelper.info(
          'Place: ${place.title} - Category: ${place.categoryId} - Lat: ${place.latitude} - Lng: ${place.longitude}',
        );
      }

      displayedPlaces.assignAll(availablePlaces);
      createPlaceMarkers();

      // Check if places have valid coordinates
      final placesWithCoords = availablePlaces
          .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
          .length;
      AppLoggerHelper.info('Places with valid coordinates: $placesWithCoords');
    } catch (e) {
      AppLoggerHelper.error('Error loading places: $e');
      Get.snackbar(
        // 'Loading Error',
        txt.errorLoading,
        // 'Could not load places',
        txt.couldNotLoadPlaces,
        // txt.could
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> createPlaceMarkers() async {
    markers.clear();

    // Add current location marker if available
    if (currentLocation.value?.latitude != null) {
      final currentLocationMarker = Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(
          currentLocation.value!.latitude!,
          currentLocation.value!.longitude!,
        ),
        icon: await CustomMarkerGenerator.getCurrentLocationMarker(),
        // infoWindow: const InfoWindow(title: 'Your Location'),
        infoWindow: InfoWindow(title: txt.yourLocation),
        zIndexInt: 1000,
        anchor: const Offset(0.5, 0.5),
      );
      markers.add(currentLocationMarker);
    }

    // Add place markers
    for (final place in displayedPlaces) {
      if (place.latitude == 0.0 || place.longitude == 0.0) continue;

      final isSelected = selectedPlace.value?.id == place.id;
      final marker = Marker(
        markerId: MarkerId('place_${place.id}'),
        position: LatLng(place.latitude, place.longitude),
        infoWindow: InfoWindow(
          title: place.title,
          snippet: '${place.averageRating} ⭐ • ${place.address.shortAddress}',
          onTap: () => _onPlaceMarkerTapped(place),
        ),
        icon: await CustomMarkerGenerator.generatePlaceMarker(
          place,
          isSelected: isSelected,
        ),
        onTap: () => _onPlaceMarkerTapped(place),
        zIndexInt: isSelected ? 1000 : 1,
        anchor: const Offset(0.5, 1.0), // Anchor at bottom center for pointer
      );

      markers.add(marker);
    }
    markers.refresh();
  }

  void _addHighlightMarker(PlaceModel place) {
    final _ = MarkerId('highlighted_${place.id}');

    // Remove any existing highlight marker
    markers.removeWhere((m) => m.markerId.value.startsWith('highlighted_'));

    // Recreate the selected marker with highlighted style
    createPlaceMarkers(); // This will recreate all markers with proper selection state
  }

  void _onPlaceMarkerTapped(PlaceModel place) {
    selectedPlace.value = place;
    showBottomSheet.value = true;
    showLocationDetails.value = true;

    // Calculate distance from user to this place
    calculateDistanceToPlace();

    // Move camera to place with nice animation
    moveCameraToLatLng(LatLng(place.latitude, place.longitude), zoom: 16.0);

    // Update markers to show selection
    createPlaceMarkers();

    // Log for debugging
    AppLoggerHelper.info('Marker tapped: ${place.title}');
  }

  // Updated moveCameraToLatLng with optional zoom
  void moveCameraToLatLng(LatLng target, {double? zoom}) {
    googleMapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom ?? 15.0,
          bearing: 0,
          // tilt: isPickerMode ? 0 : 45, // Slight tilt for better view
          tilt: 45,
        ),
      ),
    );
  }

  /// Handle camera movement to update coordinates display
  void onCameraMove(CameraPosition position) {
    currentMapCenter.value = position.target;
    currentZoomLevel.value = position.zoom;
  }

  /// Calculate distance from user location to selected place
  void calculateDistanceToPlace() {
    if (currentLocation.value == null || selectedPlace.value == null) {
      distanceToSelectedPlace.value = 0.0;
      return;
    }

    final userLat = currentLocation.value!.latitude!;
    final userLng = currentLocation.value!.longitude!;
    final placeLat = selectedPlace.value!.latitude;
    final placeLng = selectedPlace.value!.longitude;

    distanceToSelectedPlace.value = DirectionsService.calculateDistance(
      LatLng(userLat, userLng),
      LatLng(placeLat, placeLng),
    );
  }

  // --- ENHANCED SEARCH WITH PLACES INTEGRATION ---
  void onSearchQueryChanged(String query) {
    searchQuery.value = query;
    _searchDebounceTimer?.cancel();

    if (query.isEmpty) {
      searchSuggestions.clear();
      isSearching.value = false;
      _filterPlacesBySearch('');
      return;
    }

    isSearching.value = true;
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performEnhancedSearch(query);
    });
  }

  void _filterPlacesBySearch(String query) {
    if (query.isEmpty) {
      displayedPlaces.assignAll(placeController.places);
    } else {
      final filtered = placeController.places.where((place) {
        return place.title.toLowerCase().contains(query.toLowerCase()) ||
            place.description.toLowerCase().contains(query.toLowerCase()) ||
            place.address.shortAddress.toLowerCase().contains(
              query.toLowerCase(),
            );
      }).toList();
      displayedPlaces.assignAll(filtered);
    }
    createPlaceMarkers();
  }

  // Enhanced search with database + Google API integration
  Future<void> _performEnhancedSearch(String query) async {
    try {
      final List<SearchSuggestion> allSuggestions = [];

      // 1. Search in our local database first
      final localPlaceSuggestions = _searchLocalPlaces(query);
      allSuggestions.addAll(localPlaceSuggestions);

      // 2. If we have few local results, search Google Places
      if (localPlaceSuggestions.length < 5) {
        try {
          final googleResults = await GooglePlacesService.searchPlaces(
            query,
            location: currentLocation.value != null
                ? LatLng(
                    currentLocation.value!.latitude!,
                    currentLocation.value!.longitude!,
                  )
                : null,
          );

          // Filter out duplicates with local results
          final uniqueGoogleResults = googleResults.where((googleSuggestion) {
            return !localPlaceSuggestions.any(
              (localSuggestion) =>
                  localSuggestion.title.toLowerCase() ==
                  googleSuggestion.title.toLowerCase(),
            );
          }).toList();

          allSuggestions.addAll(uniqueGoogleResults);
        } catch (e) {
          AppLoggerHelper.error('Google Places search error: $e');
        }
      }

      // 3. Add recent searches
      final recentMatches = recentSearches
          .where(
            (search) =>
                search.query.toLowerCase().contains(query.toLowerCase()),
          )
          .take(3)
          .map(
            (recent) => SearchSuggestion(
              id: recent.id,
              title: recent.query,
              subtitle: recent.address,
              type: 'recent',
              icon: 'history',
            ),
          )
          .toList();
      allSuggestions.addAll(recentMatches);

      // 4. Add current location option for relevant queries
      if (_isCurrentLocationQuery(query)) {
        allSuggestions.insert(
          0,
          SearchSuggestion(
            id: 'current_location',
            // title: 'Your Current Location',
            title: txt.currentLocation,
            // subtitle: 'Based on your device location',
            subtitle: txt.recommendationBasedOnLocation,
            type: 'current_location',
            icon: 'my_location',
          ),
        );
      }

      searchSuggestions.assignAll(allSuggestions);
      _saveToRecentSearches(query, type: 'search');
    } catch (e) {
      AppLoggerHelper.error('Enhanced search error: $e');
      searchSuggestions.clear();
    } finally {
      isSearching.value = false;
    }
  }

  bool _isCurrentLocationQuery(String query) {
    final locationKeywords = [
      'current',
      'my location',
      'near me',
      'nearby',
      'around me',
      'close to me',
    ];
    return locationKeywords.any(
      (keyword) => query.toLowerCase().contains(keyword),
    );
  }

  // Improved local places search
  List<SearchSuggestion> _searchLocalPlaces(String query) {
    if (query.isEmpty) return [];

    final results = placeController.places.where((place) {
      final searchableText =
          '''
      ${place.title} 
      ${place.description} 
      ${place.address.shortAddress}
      ${place.tags?.join(' ') ?? ''}
      ${_getCategoryName(place.categoryId)}
    '''
              .toLowerCase();

      return searchableText.contains(query.toLowerCase());
    }).toList();

    // Sort by relevance (title matches first, then description, then address)
    results.sort((a, b) {
      final aTitleMatch = a.title.toLowerCase().contains(query.toLowerCase());
      final bTitleMatch = b.title.toLowerCase().contains(query.toLowerCase());

      if (aTitleMatch && !bTitleMatch) return -1;
      if (!aTitleMatch && bTitleMatch) return 1;

      return a.title.compareTo(b.title);
    });

    return results
        .map((place) => SearchSuggestion.fromPlaceModel(place))
        .toList();
  }

  String _getCategoryName(String categoryId) {
    try {
      final category = categoryController.allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => CategoryModel.empty(),
      );
      return category.name;
    } catch (e) {
      return '';
    }
  }

  // --- CATEGORY FILTERING ---
  void filterByCategory(String categoryId) {
    try {
      selectedCategoryId.value = categoryId;

      AppLoggerHelper.info('Filtering by category: $categoryId');
      AppLoggerHelper.info(
        'Total places available: ${placeController.places.length}',
      );

      if (categoryId.isEmpty) {
        // Show all places
        displayedPlaces.assignAll(placeController.places);
        AppLoggerHelper.info('Showing all places: ${displayedPlaces.length}');
      } else {
        // Filter by category
        final filteredPlaces = placeController.places.where((place) {
          return place.categoryId == categoryId;
        }).toList();
        displayedPlaces.assignAll(filteredPlaces);
        AppLoggerHelper.info(
          'Filtered places count: ${displayedPlaces.length}',
        );
      }

      createPlaceMarkers();

      // Zoom to fit places
      if (displayedPlaces.isNotEmpty) {
        // Small delay to ensure markers are created
        Future.delayed(const Duration(milliseconds: 100), () {
          final bounds = _createBoundsForPlaces(displayedPlaces);
          _zoomToBounds(bounds);
        });
      } else {
        AppLoggerHelper.warning('No places found for category: $categoryId');
        AppLoaders.warningSnackBar(
          // title: 'No Places Found',
          // message: 'No places found for the selected category',
          title: txt.noPlacesFound,
          message: txt.noPlacesFoundForCategory,
        );
      }
    } catch (e) {
      AppLoggerHelper.error('Category filtering error: $e');
      AppLoaders.errorSnackBar(
        // title: 'Filter Error',
        // message: 'Could not filter places by category',
        title: txt.filterError, // Instead of 'Filter Error'
        message: txt.couldNotFilterPlaces,
      );
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // Earth's radius in meters

    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final deltaLatRad = _degreesToRadians(lat2 - lat1);
    final deltaLonRad = _degreesToRadians(lon2 - lon1);

    final a =
        sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLonRad / 2) *
            sin(deltaLonRad / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  // Enhanced nearby places with radius filtering
  Future<void> loadNearbyPlaces({double? customRadius}) async {
    if (currentLocation.value == null) {
      AppLoaders.warningSnackBar(
        // title: 'Location Required',
        // message: 'Please wait for your location to load',
        title: txt.locationRequired,
        message: txt.pleaseWaitForLocation,
      );
      return;
    }

    try {
      isLoading.value = true;
      final currentLatLng = LatLng(
        currentLocation.value!.latitude!,
        currentLocation.value!.longitude!,
      );

      // Use custom radius or default
      final radius = customRadius ?? searchRadius.value;

      // Filter places within radius
      final nearby = displayedPlaces.where((place) {
        if (place.latitude == 0.0 || place.longitude == 0.0) return false;

        final distance = _calculateDistance(
          currentLatLng.latitude,
          currentLatLng.longitude,
          place.latitude,
          place.longitude,
        );
        return distance <= radius;
      }).toList();

      // Sort by distance
      nearby.sort((a, b) {
        final distanceA = _calculateDistance(
          currentLatLng.latitude,
          currentLatLng.longitude,
          a.latitude,
          a.longitude,
        );
        final distanceB = _calculateDistance(
          currentLatLng.latitude,
          currentLatLng.longitude,
          b.latitude,
          b.longitude,
        );
        return distanceA.compareTo(distanceB);
      });

      nearbyPlaces.assignAll(nearby);

      AppLoggerHelper.info(
        'Found ${nearbyPlaces.length} nearby places within ${radius}m',
      );

      // Show results
      if (nearbyPlaces.isNotEmpty) {
        // Create bounds to show all nearby places
        final bounds = _createBoundsForPlaces(nearbyPlaces);
        _zoomToBounds(bounds);

        AppLoaders.successSnackBar(
          // 'Nearby Places',
          // 'Found ${nearbyPlaces.length} places nearby',
          title: txt.nearbyPlaces, // Instead of 'Nearby Places'
          message: txt.foundPlacesNearby(nearbyPlaces.length),
        );
      } else {
        AppLoaders.warningSnackBar(
          // 'No Places Found',
          // 'No places found within ${(radius / 1000).toStringAsFixed(1)}km',
          title: txt.noPlacesFound,
          message: txt.noPlacesFoundWithinDistance(
            radius / 1000,
          ), // Instead of hardcoded text
        );
      }
    } catch (e) {
      AppLoggerHelper.error('Error loading nearby places: $e');
      AppLoaders.errorSnackBar(
        // 'Error',
        // 'Could not load nearby places',
        // backgroundColor: AppColors.error,
        title: txt.error,
        message: txt.errorLoadingNearbyPlaces,
      );
    } finally {
      isLoading.value = false;
    }
  }

  LatLngBounds _createBoundsForPlaces(List<PlaceModel> places) {
    double? minLat, maxLat, minLng, maxLng;

    for (final place in places) {
      if (place.latitude == 0.0 || place.longitude == 0.0) continue;

      minLat = minLat == null ? place.latitude : min(minLat, place.latitude);
      maxLat = maxLat == null ? place.latitude : max(maxLat, place.latitude);
      minLng = minLng == null ? place.longitude : min(minLng, place.longitude);
      maxLng = maxLng == null ? place.longitude : max(maxLng, place.longitude);
    }

    // Add padding
    const padding = 0.01;
    minLat = (minLat ?? 0) - padding;
    maxLat = (maxLat ?? 0) + padding;
    minLng = (minLng ?? 0) - padding;
    maxLng = (maxLng ?? 0) + padding;

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _zoomToBounds(LatLngBounds bounds) async {
    final controller = await mapControllerCompleter.future;
    final cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 100);
    await controller.animateCamera(cameraUpdate);
  }

  // --- SUGGESTION SELECTION HANDLING ---
  Future<void> onSuggestionSelected(SearchSuggestion suggestion) async {
    searchQuery.value = suggestion.title;
    searchController.text = suggestion.title;
    searchSuggestions.clear();
    isSearching.value = false;

    _saveToRecentSearches(
      suggestion.title,
      type: suggestion.type,
      placeId: suggestion.placeId,
      location: suggestion.location,
      address: suggestion.subtitle,
    );

    try {
      switch (suggestion.type) {
        case 'current_location':
          moveToCurrentLocation();
          break;

        case 'local_place':
          // Find and select the local place
          final place = displayedPlaces.firstWhere(
            (p) => p.id == suggestion.id,
            orElse: () => PlaceModel.empty(),
          );
          if (place.id.isNotEmpty) {
            _onPlaceMarkerTapped(place);
          }
          break;

        case 'google_place':
          await _handleGooglePlaceSuggestion(suggestion);
          break;

        case 'address':
          await _handleAddressSuggestion(suggestion);
          break;

        case 'recent':
          onSearchQueryChanged(suggestion.title);
          break;
      }
    } catch (e) {
      AppLoggerHelper.error('Suggestion selection error: $e');
      AppLoaders.errorSnackBar(
        // 'Error',
        // 'Could not load location details',
        title: txt.error,
        message: txt.errorLoadingLocationDetails,
      );
    }
  }

  Future<void> _handleGooglePlaceSuggestion(SearchSuggestion suggestion) async {
    if (suggestion.placeId != null) {
      final details = await GooglePlacesService.getPlaceDetails(
        suggestion.placeId!,
      );
      if (details != null) {
        moveCameraToLatLng(details.location);
        _addMarkerForLocation(details.location, details.name);

        // Create a temporary place from Google Places data
        final tempPlace = _createTemporaryPlaceFromGoogleDetails(
          details,
          suggestion,
        );
        _showPlaceDetails(tempPlace);
      }
    } else if (suggestion.location != null) {
      moveCameraToLatLng(suggestion.location!);
      _addMarkerForLocation(suggestion.location!, suggestion.title);

      final tempPlace = _createTemporaryPlaceFromSuggestion(suggestion);
      _showPlaceDetails(tempPlace);
    }
  }

  Future<void> _handleAddressSuggestion(SearchSuggestion suggestion) async {
    if (suggestion.location != null) {
      moveCameraToLatLng(suggestion.location!);
      _addMarkerForLocation(suggestion.location!, suggestion.title);

      final address = await GooglePlacesService.getAddressFromLatLng(
        suggestion.location!,
      );
      final tempPlace = _createTemporaryPlaceFromSuggestion(
        suggestion,
        address: address,
      );
      _showPlaceDetails(tempPlace);
    }
  }

  PlaceModel _createTemporaryPlaceFromSuggestion(
    SearchSuggestion suggestion, {
    String? address,
  }) {
    return PlaceModel(
      id: 'temp_${suggestion.id}',
      title: suggestion.title,
      description: address ?? suggestion.subtitle ?? 'Location from search',
      address: AddressModel(
        id: 'temp_address_${suggestion.id}',
        name: suggestion.title,
        phoneNumber: '',
        street: _extractStreetFromAddress(address ?? suggestion.subtitle ?? ''),
        city: _extractCityFromAddress(address ?? suggestion.subtitle ?? ''),
        state: '',
        postalCode: '',
        country: _extractCountryFromAddress(
          address ?? suggestion.subtitle ?? '',
        ),
        latitude: suggestion.location?.latitude ?? 0.0,
        longitude: suggestion.location?.longitude ?? 0.0,
      ),
      categoryId: 'other',
      averageRating: suggestion.rating ?? 0.0,
      reviewsCount: suggestion.reviewCount ?? 0,
      userId: 'search_system',
      thumbnail: suggestion.photoReference != null
          ? GooglePlacesService.getPlacePhotoUrl(suggestion.photoReference!)
          : '',
      isFeatured: false,
      creatorName: 'Search Result',
      creatorAvatarUrl: '',
      likeCount: 0,
      followerCount: 0,
    );
  }

  PlaceModel _createTemporaryPlaceFromGoogleDetails(
    GooglePlaceDetails details,
    SearchSuggestion suggestion,
  ) {
    return PlaceModel(
      id: 'google_${details.placeId ?? suggestion.id}',
      title: details.name,
      description: details.address ?? 'Google Places location',
      address: AddressModel(
        id: 'google_address_${details.placeId}',
        name: details.name,
        phoneNumber: details.formattedPhoneNumber ?? '',
        street: _extractStreetFromAddress(details.address ?? ''),
        city: _extractCityFromAddress(details.address ?? ''),
        state: '',
        postalCode: '',
        country: _extractCountryFromAddress(details.address ?? ''),
        latitude: details.location.latitude,
        longitude: details.location.longitude,
      ),
      categoryId: details.category ?? 'other',
      averageRating: details.rating ?? 0.0,
      reviewsCount: details.totalRatings ?? 0,
      userId: 'google_places',
      thumbnail: details.photos.isNotEmpty ? details.photos.first : '',
      isFeatured: false,
      creatorName: 'Google Places',
      creatorAvatarUrl: '',
      likeCount: 0,
      followerCount: 0,
    );
  }

  void _showPlaceDetails(PlaceModel place) {
    selectedPlace.value = place;
    showBottomSheet.value = true;
    showLocationDetails.value = true;

    if (place.latitude != 0.0 && place.longitude != 0.0) {
      _addHighlightMarker(place);
    }
  }

  // --- VOICE SEARCH FUNCTIONALITY ---
  void startListening() async {
    if (await speech.hasPermission && !isListening.value) {
      isListening.value = true;
      speechText.value = '';
      speech.listen(
        onResult: (result) {
          speechText.value = result.recognizedWords;
          if (result.finalResult) {
            searchController.text = result.recognizedWords;
            onSearchQueryChanged(result.recognizedWords);
            isListening.value = false;
          }
        },
        listenFor: const Duration(seconds: 30),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } else {
      final status = await speech.initialize();
      if (status) {
        startListening();
      }
    }
  }

  void stopListening() {
    isListening.value = false;
    speech.stop();
  }

  // --- MAP FUNCTIONALITY ---
  void onMapCreated(GoogleMapController controller) async {
    if (!mapControllerCompleter.isCompleted) {
      googleMapController = controller;
      mapControllerCompleter.complete(controller);

      // Note: Map style is now applied via GoogleMap(style: ...) property
      // in the widget tree, reacting to currentMapStyle changes.

      await Future.delayed(const Duration(milliseconds: 1000));
      _performInitialMapSetup();
    }
  }

  void _performInitialMapSetup() {
    if (_isInitialMapSetupComplete) return;

    // If we have an initial place to show, prioritize it
    if (initialPlace != null) {
      // Ensure the place is in the displayed list so a marker is created
      if (!displayedPlaces.any((p) => p.id == initialPlace!.id)) {
        displayedPlaces.add(initialPlace!);
      }

      selectedPlace.value = initialPlace;
      showBottomSheet.value = true;

      // Move camera to the place location
      if (initialPlace!.latitude != 0.0 && initialPlace!.longitude != 0.0) {
        final target = LatLng(initialPlace!.latitude, initialPlace!.longitude);
        moveCameraToLatLng(target, zoom: 16.0);
      }

      // Recreate markers to show the selected state
      createPlaceMarkers();

      // Clear initialPlace after handling
      initialPlace = null;
    } else {
      // Default behavior: move to current location
      final targetLocation = currentLocation.value;
      if (targetLocation?.latitude != null) {
        final target = LatLng(
          targetLocation!.latitude!,
          targetLocation.longitude!,
        );
        moveCameraToLatLng(target);
      }
    }

    _isInitialMapSetupComplete = true;
  }

  void setInitialPlace(PlaceModel place) {
    initialPlace = place;
    _isInitialMapSetupComplete = false;

    // If map is already created, trigger setup immediately
    if (googleMapController != null) {
      _performInitialMapSetup();
    }
  }

  void moveToCurrentLocation() {
    if (currentLocation.value?.latitude != null) {
      final latLng = LatLng(
        currentLocation.value!.latitude!,
        currentLocation.value!.longitude!,
      );
      moveCameraToLatLng(latLng);
    }
  }

  void onMapTap(LatLng position) {
    if (!showBottomSheet.value) {
      pickedLocation.value = position;
      _updateSelectionMarker(position);
      _getLocationName(position.latitude, position.longitude);
    }
  }

  // Animate marker selection
  void animateToPlace(PlaceModel place) {
    if (place.latitude == 0.0 || place.longitude == 0.0) return;

    // Move camera to place
    moveCameraToLatLng(LatLng(place.latitude, place.longitude));

    // Highlight the place
    _onPlaceMarkerTapped(place);

    // Add bounce animation
    _bounceMarker(place.id);
  }

  void _bounceMarker(String placeId) {
    // You can implement a simple bounce effect by scaling the marker
    // This would require recreating the marker with different sizes
    // For now, we'll just ensure it's properly highlighted
    createPlaceMarkers();
  }

  void _updateSelectionMarker(LatLng position) async {
    const markerId = MarkerId('selectedLocation');
    final selectionMarker = Marker(
      markerId: markerId,
      position: position,
      icon: await CustomMarkerGenerator.getSelectedLocationMarker(),
      // infoWindow: const InfoWindow(title: 'Selected Location'),
      infoWindow: InfoWindow(title: txt.selectedLocation),
      zIndexInt: 1000,
      anchor: const Offset(0.5, 1.0),
    );

    markers.removeWhere((m) => m.markerId == markerId);
    markers.add(selectionMarker);
    markers.refresh();
  }

  void _addMarkerForLocation(LatLng location, String title) {
    final markerId = MarkerId(
      'search_result_${location.latitude}_${location.longitude}',
    );
    final marker = Marker(
      markerId: markerId,
      position: location,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: title),
    );

    markers.removeWhere((m) => m.markerId == markerId);
    markers.add(marker);
    markers.refresh();
  }

  // --- LOCATION SERVICES ---
  void getCurrentLocation() async {
    final location = Location();

    try {
      // Check if location service is enabled
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          AppLoggerHelper.error('Location services are disabled');
          AppLoaders.warningSnackBar(
            title: txt.locationRequired,
            message: 'Please enable location services to use this feature',
          );
          return;
        }
      }

      // Check permissions
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          AppLoggerHelper.error('Location permission denied');
          AppLoaders.warningSnackBar(
            title: txt.locationRequired,
            message: 'Please grant location permission to continue',
          );
          return;
        }
      }

      // Configure location settings for better performance
      await location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000, // Update every second
        distanceFilter: 10, // Update every 10 meters
      );

      // Get initial location with timeout
      LocationData? newLocationData;
      try {
        newLocationData = await location.getLocation().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            AppLoggerHelper.warning(
              'Location fetch timeout, using last known location',
            );
            throw TimeoutException('Location fetch timeout');
          },
        );

        currentLocation.value = newLocationData;
        pickedLocation.value = LatLng(
          newLocationData.latitude!,
          newLocationData.longitude!,
        );

        if (!_isInitialMapSetupComplete) {
          _performInitialMapSetup();
        }

        // Get location name in background
        _getLocationName(newLocationData.latitude!, newLocationData.longitude!);
      } on TimeoutException {
        AppLoggerHelper.error('Location fetch timed out');
        // Try to use cached location if available
        final cachedLocation = await location.getLocation();
        if (cachedLocation.latitude != null) {
          currentLocation.value = cachedLocation;
          pickedLocation.value = LatLng(
            cachedLocation.latitude!,
            cachedLocation.longitude!,
          );
        }
      }

      // Set up location updates stream
      _locationSubscription = location.onLocationChanged.listen(
        (newLocation) {
          currentLocation.value = newLocation;
          if (googleMapController != null && _isInitialMapSetupComplete) {
            // Update location name less frequently to avoid too many API calls
            _getLocationName(newLocation.latitude!, newLocation.longitude!);
          }
        },
        onError: (error) {
          AppLoggerHelper.error('Live Location Stream Error: $error');
        },
      );
    } catch (e) {
      AppLoggerHelper.error('Location initialization error: $e');
      AppLoaders.errorSnackBar(
        title: txt.error,
        message: 'Could not get your location. Please try again.',
      );
    }
  }

  Future<void> _getLocationName(double latitude, double longitude) async {
    try {
      final address = await GooglePlacesService.getAddressFromLatLng(
        LatLng(latitude, longitude),
      );
      locationName.value = address ?? txt.unknownLocation;
    } catch (e) {
      AppLoggerHelper.error('Reverse Geocoding Error: $e');
      // locationName.value = 'Location name not found';
      locationName.value = txt.locationNameNotFound;
    }
  }

  // --- UI CONTROLS ---
  void changeMapType(MapType newType) async {
    currentMapType.value = newType;
  }

  void toggleMapDetail(MapDetail detail) {
    if (enabledMapDetails.contains(detail)) {
      enabledMapDetails.remove(detail);
    } else {
      enabledMapDetails.add(detail);
    }
    enabledMapDetails.refresh();
  }

  MapType get googleMapType {
    switch (currentMapType.value) {
      case MapType.satellite:
        return MapType.satellite;
      case MapType.terrain:
        return MapType.terrain;
      case MapType.hybrid:
        return MapType.hybrid;
      default:
        return MapType.normal;
    }
  }

  void clearSearch() {
    searchController.clear();
    searchQuery.value = '';
    searchSuggestions.clear();
    isSearching.value = false;
    showLocationDetails.value = false;
    selectedPlace.value = null;
    showBottomSheet.value = false;

    // Remove search result markers but keep place markers
    markers.removeWhere((m) => m.markerId.value.startsWith('search_result'));
    markers.refresh();

    // Reset to show all places
    displayedPlaces.assignAll(placeController.places);
    createPlaceMarkers();
  }

  // --- RECENT SEARCHES ---
  void _saveToRecentSearches(
    String query, {
    String type = 'search',
    String? placeId,
    LatLng? location,
    String? address,
  }) {
    final recent = RecentSearch(
      id: const Uuid().v4(),
      query: query,
      placeId: placeId,
      location: location,
      address: address,
      timestamp: DateTime.now(),
      type: type,
    );

    recentSearches.insert(0, recent);
    if (recentSearches.length > 20) {
      recentSearches.removeLast();
    }
  }

  void _loadRecentSearches() {
    // Load from storage or use sample searches from various categories
    // In production, this would load from local storage
    final sampleSearches = <RecentSearch>[];

    // Get a diverse set of places from different categories
    final categorizedPlaces = <String, List<PlaceModel>>{};
    for (final place in placeController.places.take(20)) {
      if (!categorizedPlaces.containsKey(place.categoryId)) {
        categorizedPlaces[place.categoryId] = [];
      }
      if (categorizedPlaces[place.categoryId]!.length < 2) {
        categorizedPlaces[place.categoryId]!.add(place);
      }
    }

    // Create recent searches from diverse places
    int index = 0;
    for (final entry in categorizedPlaces.entries.take(5)) {
      for (final place in entry.value) {
        sampleSearches.add(
          RecentSearch(
            id: 'recent_${index++}',
            query: place.title,
            placeId: place.id,
            location: LatLng(place.latitude, place.longitude),
            address: place.address.shortAddress,
            type: 'place',
            timestamp: DateTime.now().subtract(Duration(hours: index)),
          ),
        );
      }
    }

    recentSearches.addAll(sampleSearches);
  }

  // --- PICKER MODE FUNCTIONALITY ---
  void savePickedLocation() {
    if (pickedLocation.value == null) return;

    final LatLng position = pickedLocation.value!;

    final newMapAddress = AddressModel(
      id: 'Map_${const Uuid().v4()}',
      name: locationName.value.isNotEmpty
          ? locationName.value
          : txt.mapLocation,
      phoneNumber: 'N/A',
      street: _extractStreetFromAddress(locationName.value),
      city: _extractCityFromAddress(locationName.value),
      state: '',
      postalCode: '',
      country: _extractCountryFromAddress(locationName.value),
      latitude: position.latitude,
      longitude: position.longitude,
      selectedAddress: true,
    );

    Get.back(result: newMapAddress);
  }

  String _extractStreetFromAddress(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    return parts.isNotEmpty ? parts.first.trim() : '';
  }

  String _extractCityFromAddress(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    return parts.length > 1 ? parts[1].trim() : '';
  }

  String _extractCountryFromAddress(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    return parts.isNotEmpty ? parts.last.trim() : '';
  }

  // --- DIRECTIONS & ROUTING ---

  /// Fetch and display directions to a place
  Future<void> getDirectionsToPlace(PlaceModel place) async {
    if (currentLocation.value == null) {
      AppLoaders.warningSnackBar(
        title: txt.locationRequired,
        message: txt.pleaseWaitForLocation,
      );
      return;
    }

    try {
      isLoadingDirections.value = true;

      final origin = LatLng(
        currentLocation.value!.latitude!,
        currentLocation.value!.longitude!,
      );
      final destination = LatLng(place.latitude, place.longitude);

      final directions = await DirectionsService.getDirections(
        origin: origin,
        destination: destination,
        alternatives: true,
      );

      if (directions != null && directions.routes.isNotEmpty) {
        currentDirections.value = directions;
        showDirections.value = true;
        selectedRouteIndex.value = 0;

        // Draw polyline for the first route
        _drawRoutePolyline(directions.routes[0]);

        // Zoom to show the entire route
        _zoomToBounds(directions.routes[0].bounds);

        AppLoaders.successSnackBar(
          title: txt.directionsFound,
          message: txt.routeReady(place.title),
        );
      } else {
        AppLoaders.warningSnackBar(
          title: txt.noRouteFound,
          message: txt.couldNotFindRoute,
        );
      }
    } catch (e) {
      AppLoggerHelper.error('Error fetching directions: $e');
      AppLoaders.errorSnackBar(
        title: txt.error,
        message: txt.couldNotFetchDirections,
      );
    } finally {
      isLoadingDirections.value = false;
    }
  }

  /// Draw polyline for a route
  void _drawRoutePolyline(RouteModel route) {
    polylines.clear();

    final polyline = Polyline(
      polylineId: const PolylineId('main_route'),
      points: route.polylinePoints,
      color: MapStyles.activeRouteColor,
      width: MapStyles.routePolylineWidth,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    polylines.add(polyline);
    polylines.refresh();
  }

  /// Clear directions and polylines
  void clearDirections() {
    currentDirections.value = null;
    showDirections.value = false;
    polylines.clear();
    selectedRouteIndex.value = 0;
  }

  /// Switch to alternative route
  void selectRoute(int index) {
    if (currentDirections.value != null &&
        index < currentDirections.value!.routes.length) {
      selectedRouteIndex.value = index;
      _drawRoutePolyline(currentDirections.value!.routes[index]);
      _zoomToBounds(currentDirections.value!.routes[index].bounds);
    }
  }

  /// Set distance radius filter
  void setDistanceRadius(double? radiusInMeters) {
    if (radiusInMeters == null) {
      // Clear distance filter
      searchFilters.value = searchFilters.value.copyWith(
        radiusInMeters: null,
        enableDistanceFilter: false,
      );
    } else {
      searchFilters.value = searchFilters.value.copyWith(
        radiusInMeters: radiusInMeters,
        enableDistanceFilter: true,
      );
    }
  }

  /// Toggle area filter (search in visible map bounds)
  void toggleAreaFilter() {
    final currentValue = searchFilters.value.enableAreaFilter;
    if (!currentValue && googleMapController != null) {
      // Enable: Get current map bounds
      googleMapController!.getVisibleRegion().then((bounds) {
        searchFilters.value = searchFilters.value.copyWith(
          areaBounds: bounds,
          enableAreaFilter: true,
        );
      });
    } else {
      // Disable
      searchFilters.value = searchFilters.value.copyWith(
        areaBounds: null,
        enableAreaFilter: false,
      );
    }
  }

  /// Toggle nearby filter
  void toggleNearbyFilter() {
    searchFilters.value = searchFilters.value.copyWith(
      nearbyOnly: !searchFilters.value.nearbyOnly,
    );
  }

  /// Toggle highest rated filter
  void toggleHighestRatedFilter() {
    searchFilters.value = searchFilters.value.copyWith(
      highestRatedOnly: !searchFilters.value.highestRatedOnly,
    );
  }

  /// Toggle most popular filter
  void toggleMostPopularFilter() {
    searchFilters.value = searchFilters.value.copyWith(
      mostPopularOnly: !searchFilters.value.mostPopularOnly,
    );
  }

  /// Toggle recently added filter
  void toggleRecentlyAddedFilter() {
    searchFilters.value = searchFilters.value.copyWith(
      recentlyAddedOnly: !searchFilters.value.recentlyAddedOnly,
    );
  }

  /// Clear all filters
  void clearAllFilters() {
    searchFilters.value = SearchFilterModel.empty();
    applyFilters();
  }

  /// Apply current filters to places
  void applyFilters() {
    List<PlaceModel> places = List.from(placeController.places);

    // Apply category filter first
    if (selectedCategoryId.value.isNotEmpty) {
      places = places
          .where((place) => place.categoryId == selectedCategoryId.value)
          .toList();
    }

    // Apply distance radius filter
    if (searchFilters.value.enableDistanceFilter &&
        searchFilters.value.radiusInMeters != null &&
        currentLocation.value != null) {
      final userLat = currentLocation.value!.latitude!;
      final userLng = currentLocation.value!.longitude!;
      final radiusInMeters = searchFilters.value.radiusInMeters!;

      places = places.where((place) {
        final distance = DirectionsService.calculateDistance(
          LatLng(userLat, userLng),
          LatLng(place.latitude, place.longitude),
        );
        return distance <= radiusInMeters;
      }).toList();
    }

    // Apply area bounds filter
    if (searchFilters.value.enableAreaFilter &&
        searchFilters.value.areaBounds != null) {
      final bounds = searchFilters.value.areaBounds!;
      places = places.where((place) {
        final lat = place.latitude;
        final lng = place.longitude;
        return lat >= bounds.southwest.latitude &&
            lat <= bounds.northeast.latitude &&
            lng >= bounds.southwest.longitude &&
            lng <= bounds.northeast.longitude;
      }).toList();
    }

    // Apply quick filters
    if (searchFilters.value.nearbyOnly && currentLocation.value != null) {
      final userLat = currentLocation.value!.latitude!;
      final userLng = currentLocation.value!.longitude!;
      const nearbyRadius = 2000.0; // 2km for "nearby"

      places = places.where((place) {
        final distance = DirectionsService.calculateDistance(
          LatLng(userLat, userLng),
          LatLng(place.latitude, place.longitude),
        );
        return distance <= nearbyRadius;
      }).toList();
    }

    if (searchFilters.value.highestRatedOnly) {
      places = places.where((place) => place.averageRating >= 4.0).toList();
      places.sort((a, b) => b.averageRating.compareTo(a.averageRating));
    }

    if (searchFilters.value.mostPopularOnly) {
      places.sort((a, b) => b.reviewsCount.compareTo(a.reviewsCount));
      places = places.take(20).toList(); // Top 20 most popular
    }

    if (searchFilters.value.recentlyAddedOnly) {
      // Filter places with valid dates first
      places = places.where((place) => place.dateAdded != null).toList();
      places.sort((a, b) => b.dateAdded!.compareTo(a.dateAdded!));
      places = places.take(20).toList(); // 20 most recent
    }

    // Update displayed places (markers will update automatically via the map widget)
    displayedPlaces.value = places;

    AppLoggerHelper.info(
      'Filters applied. Showing ${places.length} places. Filter: ${searchFilters.value.getFilterDescription()}',
    );
  }

  // --- CLEANUP ---
  @override
  void onClose() {
    searchController.dispose();
    _locationSubscription?.cancel();
    _searchDebounceTimer?.cancel();
    speech.stop();
    if (googleMapController != null) {
      googleMapController!.dispose();
    }
    super.onClose();
  }
}
