// import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:reviews_app/data/repositories/authentication/authentication_repository.dart';
import 'package:reviews_app/features/review/models/place_category_model.dart';
import 'package:reviews_app/features/review/models/place_model.dart';
import 'package:reviews_app/localization/app_localizations.dart';
import 'package:reviews_app/utils/exceptions/format_exceptions.dart';
import 'package:reviews_app/utils/exceptions/platform_exceptions.dart';

import '../../../utils/exceptions/firebase_exceptions.dart';
import 'place_batch_writer.dart';

class PlaceRepository extends GetxController {
  static PlaceRepository get instance => Get.find();

  /// Variables
  final _db = FirebaseFirestore.instance;

  // get the current userId
  String get getCurrentUserId => AuthenticationRepository.instance.getUserID;

  /// -- Get Limited Featured Places
  Future<List<PlaceModel>> getFeaturedPlaces({int limit = 4}) async {
    try {
      final snapshot = await _db
          .collection('Places')
          .where('IsFeatured', isEqualTo: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((doc) => PlaceModel.fromSnapshot(doc)).toList();
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      throw 'Something went wrong. Please try again.';
    }
  }

  /// Returns a Stream that updates whenever the list of featured places changes.
  Stream<List<PlaceModel>> getFeaturedPlacesStream() {
    try {
      return _db
          .collection('Places')
          .where('IsFeatured', isEqualTo: true)
          .snapshots() // Get the real-time stream
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => PlaceModel.fromSnapshot(doc))
                .toList();
          });
    } on FirebaseException catch (e) {
      // It's generally better to let the error propagate up the stream,
      // but here we wrap it for consistency if needed downstream.
      throw AppFirebaseException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while streaming featured places.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get Real-Time Stream of Places by Category
  /// Returns a Stream that updates whenever the places in the specified category change.
  /// This performs a two-step query using Firestore Streams.
  Stream<List<PlaceModel>> getPlacesForCategoryStream(String categoryId) {
    try {
      // 1. Get a stream of the PlaceCategory links for the given categoryId
      final placeCategoryStream = _db
          .collection('PlaceCategory')
          .where('categoryId', isEqualTo: categoryId)
          .snapshots();

      // 2. Map the stream of PlaceCategory snapshots to a stream of PlaceModels.
      return placeCategoryStream.asyncMap((placeCategoryQuery) async {
        // Extract placeIds from the PlaceCategory documents
        final placeIds = placeCategoryQuery.docs
            .map((doc) => PlaceCategoryModel.fromSnapshot(doc).placeId)
            .toList();

        // CRITICAL FIX: Firestore 'whereIn' fails on empty lists.
        if (placeIds.isEmpty) {
          return <PlaceModel>[];
        }

        // 3. Query the 'Places' collection using the extracted IDs
        // Note: Firestore 'whereIn' is limited to 10 items. Consider splitting
        // the list and merging results for production if you expect more than 10.
        final placesQuery = await _db
            .collection('Places')
            .where(
              'Id',
              whereIn: placeIds,
            ) // Assumes 'Id' field matches doc ID or PlaceModel.id
            .get();

        // 4. Convert QuerySnapshot to List<PlaceModel>
        return placesQuery.docs
            .map((doc) => PlaceModel.fromSnapshot(doc))
            .toList();
      });
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while streaming places by category.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get All Featured Places
  Future<List<PlaceModel>> getAllFeaturedPlaces() async {
    try {
      final snapshot = await _db
          .collection('Places')
          .where('IsFeatured', isEqualTo: true)
          .get();
      return snapshot.docs
          .map((querySnapshot) => PlaceModel.fromSnapshot(querySnapshot))
          .toList();
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get Places by Category
  Future<List<PlaceModel>> getPlacesByCategory(String categoryId) async {
    try {
      final snapshot = await _db
          .collection('Places')
          .where('CategoryId', isEqualTo: categoryId)
          .get();
      return snapshot.docs
          .map((querySnapshot) => PlaceModel.fromSnapshot(querySnapshot))
          .toList();
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Get Places based on the Query
  Future<List<PlaceModel>> fetchPlacesByQuery(Query query) async {
    try {
      final querySnapshot = await query.get();
      final List<PlaceModel> placeList = querySnapshot.docs
          .map((doc) => PlaceModel.fromQuerySnapshot(doc))
          .toList();
      return placeList;
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get Favorite Places based on a list of place IDs.
  Future<List<PlaceModel>> getFavoritePlaces(List<String> placeIds) async {
    try {
      final snapshot = await _db
          .collection('Places')
          .where(FieldPath.documentId, whereIn: placeIds)
          .get();

      return snapshot.docs
          .map((querySnapshot) => PlaceModel.fromSnapshot(querySnapshot))
          .toList();
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Fetches products for a specific category.
  /// If the limit is -1, retrieves all products for the category;
  ///  otherwise, limits the result based on the provided limit.
  /// Returns a list of [PlaceModel] objects.
  // Future<List<PlaceModel>> getPlacesForCategory(
  //   String categoryId, {
  //   int limit = 4,
  // }) async {
  //   try {
  //     // Query to get all documnets where placeId matches the provided categoryId & Fetch
  //     // limited or unlimited based on the limit parameter
  //     QuerySnapshot placeCategoryQuery = limit == -1
  //         ? await _db
  //               .collection('PlaceCategory')
  //               .where('categoryId', isEqualTo: categoryId)
  //               .get()
  //         : await _db
  //               .collection('PlaceCategory')
  //               .where('categoryId', isEqualTo: categoryId)
  //               .limit(limit)
  //               .get();

  //     // Extract placeIds from the documents
  //     final placeIds = placeCategoryQuery.docs
  //         .map((doc) => PlaceCategoryModel.fromSnapshot(doc).placeId)
  //         .toList();
  //     // Query to get all documents where the placeId is in the list of placeIds
  //     // FieldPath.documentId to query documents in Collection
  //     final placesQuery = await _db
  //         .collection('Places')
  //         // .where(FieldPath.documentId, whereIn: placeIds)
  //         .where('Id', whereIn: placeIds)
  //         .get();

  //     debugPrint(
  //       'Fetched ${placesQuery.docs.length} places for category $categoryId',
  //     );
  //     debugPrint('placeIds: $placeIds');

  //     // Extract relevant data from the documents
  //     List<PlaceModel> places = placesQuery.docs
  //         .map((doc) => PlaceModel.fromSnapshot(doc))
  //         .toList();

  //     return places;
  //   } on FirebaseException catch (e) {
  //     throw AppFirebaseException(e.code).message;
  //   } on PlatformException catch (e) {
  //     throw AppPlatformException(e.code).message;
  //   } catch (e) {
  //     throw 'Something went wrong. Please try again.';
  //   }
  // }

  Future<List<PlaceModel>> getPlacesForCategory(
    String categoryId, {
    int limit = 4,
  }) async {
    try {
      // 1. Query to get all documnets where placeId matches the provided categoryId & Fetch
      // limited or unlimited based on the limit parameter
      QuerySnapshot placeCategoryQuery = limit == -1
          ? await _db
                .collection('PlaceCategory')
                .where('categoryId', isEqualTo: categoryId)
                .get()
          : await _db
                .collection('PlaceCategory')
                .where('categoryId', isEqualTo: categoryId)
                .limit(limit)
                .get();

      // 2. Extract placeIds from the documents
      final placeIds = placeCategoryQuery.docs
          .map((doc) => PlaceCategoryModel.fromSnapshot(doc).placeId)
          .toList();

      // --- CRITICAL FIX: Prevent invalid `whereIn` query ---
      // If placeIds is empty, the subsequent Firebase query will fail and throw an exception.
      // We return an empty list immediately to signal 'No Data Found' successfully.
      if (placeIds.isEmpty) return [];

      // 3. Query to get all documents where the placeId is in the list of placeIds
      final placesQuery = await _db
          .collection('Places')
          // .where(FieldPath.documentId, whereIn: placeIds) // Assuming 'Id' is the document ID
          .where('Id', whereIn: placeIds)
          .get();

      debugPrint(
        'Fetched ${placesQuery.docs.length} places for category $categoryId',
      );
      debugPrint('placeIds: $placeIds');

      // 4. Extract relevant data from the documents
      List<PlaceModel> places = placesQuery.docs
          .map((doc) => PlaceModel.fromSnapshot(doc))
          .toList();

      return places;
    } on FirebaseException catch (e) {
      // Re-throw the message to be handled by the FutureBuilder's snapshot.hasError
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// not for changes within the *Place document* itself (e.g., a rating update).
  Stream<List<PlaceModel>> streamPlacesForCategory({
    required String categoryId,
  }) {
    // 1. Stream PlaceCategory documents to get the list of place IDs.
    return _db
        .collection('PlaceCategory')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .asyncMap((placeCategoryQuery) async {
          // 2. Extract placeIds from the documents
          final placeIds = placeCategoryQuery.docs
              .map((doc) => PlaceCategoryModel.fromSnapshot(doc).placeId)
              .toList();

          // 3. Use the strongly-typed, chunking helper to fetch the Places.
          // The result (Future<List<PlaceModel>>) is awaited by asyncMap,
          // which resolves the final Stream element type to List<PlaceModel>.
          return await _fetchPlacesByIds(placeIds);
        })
        .handleError((error) {
          // Handle errors specific to the stream operation
          if (error is FirebaseException) {
            throw AppFirebaseException(error.code).message;
          } else if (error is PlatformException) {
            throw AppPlatformException(error.code).message;
          }
          // throw 'Something went wrong streaming category places: $error';
          throw txt.somethingWentWrong;
        });
  }

  /// to respect the Firestore limit of 10 items in a 'whereIn' clause.
  Future<List<PlaceModel>> _fetchPlacesByIds(List<String> placeIds) async {
    if (placeIds.isEmpty) return const [];

    List<PlaceModel> allPlaces = [];
    const chunkSize = 10;

    for (int i = 0; i < placeIds.length; i += chunkSize) {
      final chunk = placeIds.sublist(
        i,
        i + chunkSize > placeIds.length ? placeIds.length : i + chunkSize,
      );

      // Use .get() (Future) for fetching, as this is used inside asyncMap
      // and guarantees a single, strongly-typed result (List<PlaceModel>).
      final placesQuery = await _db
          .collection('Places')
          .where('Id', whereIn: chunk)
          .get();

      allPlaces.addAll(
        placesQuery.docs.map((doc) => PlaceModel.fromSnapshot(doc)).toList(),
      );
    }

    return allPlaces;
  }

  /// Required for Details Screen: Stream a single Place document for real-time updates
  Stream<PlaceModel> streamSinglePlace(String placeId) {
    return _db
        .collection('Places')
        .doc(placeId)
        .snapshots()
        .map((snapshot) => PlaceModel.fromSnapshot(snapshot))
        .handleError((e) {
          if (e is FirebaseException) {
            throw AppFirebaseException(e.code).message;
          }
          // throw 'Error streaming single place: $e';
          throw txt.somethingWentWrong;
        });
  }

  /// -- Create new place
  Future<String> createPlace(PlaceModel place) async {
    String placeId = '';

    try {
      // Write the main document first to get the unique Firestore ID
      final data = await _db.collection('Places').add(place.toJson());
      placeId = data.id;

      // Update the place model with the generated ID for batch use
      final placeWithId = place.copyWith(id: placeId);

      // Instantiate the batch writer, which initializes the WriteBatch internally
      final batchWriter = PlaceBatchWriter(db: _db);

      // Call the writer's methods to add operations to the internal batch.
      if (placeWithId.images != null && placeWithId.images!.isNotEmpty) {
        batchWriter.addImagesToGallery(placeWithId);

        await batchWriter.updateCollection(placeWithId);
      }

      // 4. Commit the internal batch atomically.
      await batchWriter.commit();

      // return data.id;
      return placeId;
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    } finally {}
  }

  /// -- Create new Place Category
  Future<String> createPlaceCategory(PlaceCategoryModel placeCategory) async {
    try {
      final data = await _db
          .collection('PlaceCategory')
          .add(placeCategory.toJson());
      return data.id;
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Update place.
  Future<void> updatePlace(PlaceModel place) async {
    try {
      await _db.collection('Places').doc(place.id).update(place.toJson());
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Update Place Instance
  Future<void> updatePlaceSpecificValue(
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      await _db.collection('Places').doc(id).update(data);
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get Places Categories
  Future<List<PlaceCategoryModel>> getPlaceCategories(String placeId) async {
    try {
      final snapshot = await _db
          .collection('PlaceCategory')
          .where('placeId', isEqualTo: placeId)
          .get();
      return snapshot.docs
          .map(
            (querySnapshot) => PlaceCategoryModel.fromSnapshot(querySnapshot),
          )
          .toList();
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Remove Place category
  Future<void> removePlaceCategory(String placeId, String categoryId) async {
    try {
      final result = await _db
          .collection('PlaceCategory')
          .where('placeId', isEqualTo: placeId)
          .get();
      for (final doc in result.docs) {
        await doc.reference.delete();
      }
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Delete Place
  // Future<void> deletePlace(PlaceModel place) async {
  //   try {
  //     // delete all data at once from Firebase firestore
  //     await _db.runTransaction((transaction) async {
  //       final placeRef = _db.collection('Places').doc(place.id);
  //       final placeSnap = await transaction.get(placeRef);

  //       if (!placeSnap.exists) {
  //         throw Exception('Place not found');
  //       }

  //       // Fetch PlaceCategories
  //       final placeCategoriesSnapshot = await _db
  //           .collection('PlaceCategory')
  //           .where('placeId', isEqualTo: place.id)
  //           .get();
  //       final placeCategories = placeCategoriesSnapshot.docs
  //           .map((e) => PlaceCategoryModel.fromSnapshot(e))
  //           .toList();

  //       if (placeCategories.isNotEmpty) {
  //         for (var placeCategory in placeCategories) {
  //           transaction.delete(
  //             _db.collection('PlaceCategory').doc(placeCategory.id),
  //           );
  //         }
  //       }

  //       transaction.delete(placeRef);
  //     });
  //   } on FirebaseException catch (e) {
  //     throw AppFirebaseException(e.code).message;
  //   } on FormatException catch (_) {
  //     throw const AppFormatException();
  //   } on PlatformException catch (e) {
  //     throw AppPlatformException(e.code).message;
  //   } catch (e) {
  //     // throw 'Something went wrong. Please try again.';
  //     throw txt.somethingWentWrong;
  //   }
  // }

  /// -- Ultra Simple: Delete place and all related data
  /// -- Ultra Simple: Delete place and all related data
  Future<void> deletePlace(PlaceModel place) async {
    try {
      debugPrint('🗑️  Deleting place: ${place.title}');

      final placeId = place.id;

      // Create batch for atomic deletion
      final batch = _db.batch();
      final placeRef = _db.collection('Places').doc(placeId);

      // 1. Delete main place
      batch.delete(placeRef);

      // 2. Delete GalleryImages
      final galleryImages = await _db
          .collection('GalleryImages')
          .where('PlaceId', isEqualTo: placeId)
          .get();

      for (var doc in galleryImages.docs) {
        batch.delete(doc.reference);
      }

      // 3. Delete PlaceCategory links
      final placeCategories = await _db
          .collection('PlaceCategory')
          .where('placeId', isEqualTo: placeId)
          .get();

      for (var doc in placeCategories.docs) {
        batch.delete(doc.reference);
      }

      // 5. Delete Reviews
      final reviews = await _db
          .collection('Reviews')
          .where('placeId', isEqualTo: placeId)
          .get();
      for (var doc in reviews.docs) {
        batch.delete(doc.reference);
      }

      // 6. Delete Comments
      final comments = await _db
          .collection('Comments')
          .where('placeId', isEqualTo: placeId)
          .get();
      for (var doc in comments.docs) {
        batch.delete(doc.reference);
      }

      // 7. Delete Likes Subcollection
      final likes = await _db
          .collection('Places')
          .doc(placeId)
          .collection('Likes')
          .get();
      for (var doc in likes.docs) {
        batch.delete(doc.reference);
      }

      // Execute all at once
      await batch.commit();

      debugPrint('✅ Deleted place ${place.title} from all collections');
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on FormatException catch (_) {
      throw const AppFormatException();
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Decrements the total review count and the count for the specific rating
  /// within the RatingDistribution map when a review is **deleted**.
  /// The rating is expected to be a whole number (1-5).
  Future<void> removeReviewRating(String placeId, int ratingToRemove) async {
    try {
      final placeRef = _db.collection('Places').doc(placeId);
      final starKey = ratingToRemove.toString();

      // Basic input validation: ensure rating is within 1-5 range.
      if (ratingToRemove < 1 || ratingToRemove > 5) return;

      // Use Firestore's atomic increment feature with a negative value (-1)
      await placeRef.update({
        // 1. Decrement the total number of reviews
        'ReviewCount': FieldValue.increment(-1),
        // 2. Decrement the count for this specific star rating in the Map
        'RatingDistribution.$starKey': FieldValue.increment(-1),
      });
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while removing review rating. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Handles the change in rating when a user **edits** an existing review.
  /// It decrements the old rating's count and increments the new rating's count
  /// in the RatingDistribution map.
  ///
  /// The overall ReviewCount is NOT modified since the review still exists.
  Future<void> updateRatingChange({
    required String placeId,
    required int oldRating,
    required int newRating,
  }) async {
    // Optimization: If the ratings are the same, no database update is necessary.
    if (oldRating == newRating) return;

    try {
      final placeRef = _db.collection('Places').doc(placeId);
      final oldStarKey = oldRating.toString();
      final newStarKey = newRating.toString();

      // Basic input validation: ensure both ratings are within 1-5 range.
      if (oldRating < 1 || oldRating > 5 || newRating < 1 || newRating > 5) {
        return;
      }

      await placeRef.update({
        // 1. Decrement the count of the old rating
        'RatingDistribution.$oldStarKey': FieldValue.increment(-1),
        // 2. Increment the count of the new rating
        'RatingDistribution.$newStarKey': FieldValue.increment(1),
        // Note: ReviewCount is deliberately unchanged here.
      });
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while updating review rating change. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Updates the total review count and calculates the new average rating for a place.
  Future<void> updatePlaceRatingStatistics(
    String placeId,
    double newRating,
  ) async {
    try {
      final placeRef = _db.collection('Places').doc(placeId);

      // 1. Determine the star key (1-5) for the distribution map.
      // We round the newRating to the nearest whole number to use as the distribution key.
      final starKey = newRating.round().toString();

      // Guard: Ensure the star key is valid (1, 2, 3, 4, 5)
      if (!['1', '2', '3', '4', '5'].contains(starKey)) {
        // Log this issue if it happens, but shouldn't for typical 1-5 star systems.
        throw Exception(
          'Invalid rating value ($newRating) received for distribution update.',
        );
      }

      // 2. Use Firestore's atomic increment feature for both the total count
      // and the specific star rating count inside the RatingDistribution map.
      await placeRef.update({
        'ReviewCount': FieldValue.increment(1),
        // This syntax uses dot notation to atomically increment a value inside a Map field.
        'RatingDistribution.$starKey': FieldValue.increment(1),
      });

      // 3. IMPORTANT: We no longer need to calculate and update 'AverageRating'
      // because the PlaceModel recalculates the average from the RatingDistribution
      // every time it reads the document.
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while updating place rating. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// -- Get Single Place by ID

  Future<PlaceModel?> getPlaceById(String placeId) async {
    try {
      final documentSnapshot = await _db
          .collection('Places')
          .doc(placeId)
          .get();

      if (documentSnapshot.exists) {
        return PlaceModel.fromSnapshot(documentSnapshot);
      }

      return null;
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong. Failed to fetch place: $e';
      throw txt.somethingWentWrong;
    }
  }

  /// Firestore path to the current user's like document for a specific place.
  DocumentReference _getUserLikeDocRef(String placeId, String userId) {
    return _db
        .collection('Places')
        .doc(placeId)
        .collection('Likes')
        .doc(userId);
  }

  /// Toggles the like status and updates the count using a transaction.

  /// [isLiking] is true if the user is performing a LIKE action, false for UNLIKE.

  Future<void> togglePlaceLikeStatus(
    String placeId,
    String userId,
    bool isLiking,
  ) async {
    final likeDocRef = _getUserLikeDocRef(placeId, userId);

    final placeDocRef = _db.collection('Places').doc(placeId);

    try {
      await _db.runTransaction((transaction) async {
        // 1. Update the Like subcollection

        if (isLiking) {
          // User is liking the place, create the like document

          transaction.set(likeDocRef, {
            'UserId': userId,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // 2. Update the likeCount on the main Place document

          transaction.update(placeDocRef, {
            'LikeCount': FieldValue.increment(1),
          });
        } else {
          // User is unliking the place, delete the like document

          transaction.delete(likeDocRef);

          // 2. Update the likeCount on the main Place document

          transaction.update(placeDocRef, {
            'LikeCount': FieldValue.increment(-1),
          });
        }
      });
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while updating like status. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  /// Gets a stream of the current user's like status for a place.

  Stream<bool> getPlaceLikeStatusStream(String placeId, String userId) {
    return _getUserLikeDocRef(
      placeId,
      userId,
    ).snapshots().map((snapshot) => snapshot.exists);
  }

  /// Gets a stream of the total like count for a place.

  Stream<int> getPlaceLikeCountStream(String placeId) {
    return _db.collection('Places').doc(placeId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return (snapshot.data()!['LikeCount'] as int? ?? 0);
      }

      return 0;
    });
  }

  Future<void> debugRepositoryMethod(String placeId) async {
    try {
      debugPrint('🔧 Debugging repository method...');

      // Test if we can access Firestore directly
      final docRef = _db.collection('Places').doc(placeId);

      debugPrint('📄 Document path: ${docRef.path}');

      final document = await docRef.get();
      debugPrint('📊 Document exists: ${document.exists}');

      if (document.exists) {
        final data = document.data();
        debugPrint('📋 Document data: $data');

        if (data != null) {
          debugPrint('🏷️ Place title from direct query: ${data['title']}');
        }
      } else {
        debugPrint('❌ Document does not exist in Firestore');

        // List available places to see what's there
        final querySnapshot = await _db.collection('Places').limit(5).get();
        debugPrint('📊 Available places in database:');
        for (final doc in querySnapshot.docs) {
          debugPrint('   - ${doc.id}: ${doc.data()['title']}');
        }
      }
    } on FirebaseException catch (e) {
      throw AppFirebaseException(e.code).message;
    } on PlatformException catch (e) {
      throw AppPlatformException(e.code).message;
    } catch (e) {
      // throw 'Something went wrong while updating like status. Please try again.';
      throw txt.somethingWentWrong;
    }
  }

  Future<PlaceModel> fetchPlaceByIdDirect(String placeId) async {
    try {
      debugPrint('🚀 Using direct Firestore approach...');

      final document = await _db.collection('Places').doc(placeId).get();

      if (document.exists) {
        final data = document.data();
        if (data != null) {
          // Create PlaceModel manually to avoid repository issues
          return PlaceModel(
            id: document.id,
            title: data['Title']?.toString() ?? 'Unknown',
            description: data['Description']?.toString() ?? '',
            address: data['Address'], // You might need to handle this
            categoryId: data['CategoryId']?.toString() ?? '',
            averageRating: data['AverageRating'],
            userId: data['UserId'],
            thumbnail: data['Thumbnail'],
          );
        }
      }
      // throw Exception('Place not found');
      throw Exception(txt.noPlacesFound);
    } catch (e) {
      debugPrint('💥 Direct approach error: $e');
      rethrow;
    }
  }

  /// -- Data Repair (Run once to fix corrupted data)
  Future<void> repairData() async {
    try {
      debugPrint('🔧 Starting Data Repair...');

      // 1. Fetch ALL places
      final placesSnapshot = await _db.collection('Places').get();
      final places = placesSnapshot.docs
          .map((doc) => PlaceModel.fromSnapshot(doc))
          .toList();

      debugPrint('Found ${places.length} places to check.');

      final batch = _db.batch();
      int operationCount = 0;

      for (var place in places) {
        bool needsUpdate = false;

        // A. Fix isFeatured (Force to true)
        if (place.isFeatured != true) {
          debugPrint('Fixing isFeatured for ${place.title}');
          batch.update(_db.collection('Places').doc(place.id), {
            'IsFeatured': true,
          });
          operationCount++;
          needsUpdate = true;
        }

        // B. Fix PlaceCategory Link
        final categoryQuery = await _db
            .collection('PlaceCategory')
            .where('placeId', isEqualTo: place.id)
            .where('categoryId', isEqualTo: place.categoryId)
            .get();

        if (categoryQuery.docs.isEmpty) {
          debugPrint(
            'Restoring missing Category Link for ${place.title} (Cat: ${place.categoryId})',
          );
          final newLinkRef = _db.collection('PlaceCategory').doc();
          batch.set(newLinkRef, {
            'placeId': place.id,
            'categoryId': place.categoryId,
          });
          operationCount++;
          needsUpdate = true;
        }
      }

      if (operationCount > 0) {
        await batch.commit();
        debugPrint('✅ Data Repair Complete: Performed $operationCount fixes.');
      } else {
        debugPrint('✅ Data Repair Complete: No issues found.');
      }
    } catch (e) {
      debugPrint('❌ Data Repair Failed: $e');
    }
  }
}
