import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../../features/review/models/notification_model.dart';

class NotificationRepository extends GetxController {
  static NotificationRepository get instance => Get.find();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // NOTE: Ensure this URL points to your running Node.js server instance
  final String _serverUrl = 'https://place-api.vercel.app/send-notification';

  // Get user notifications stream
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _db
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  // --- Register FCM token via server endpoint ---
  /// Registers the FCM token by updating the user's document in Firestore.
  Future<void> registerFcmToken(String userId, String token) async {
    try {
      // Encapsulate the direct Firestore call here
      await _db.collection('Users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('FCM Token successfully registered in Firestore for user: $userId');
    } catch (e) {
      // You can handle logging or specific errors here
      print('Error registering FCM token: $e');
      rethrow; // Re-throw so the Controller can handle the UI reaction (e.g., snackbar)
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String userId, String notificationId) async {
    await _db
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _db
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // Delete notification
  Future<void> deleteNotification(String userId, String notificationId) async {
    await _db
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .doc(notificationId)
        .delete();
  }

  // Send notification via HTTP to Node.js server
  Future<void> sendNotification({
    required String toUserId,
    required String type,
    required String title,
    required String body,
    required String senderName,
    required String senderAvatar,
    required String targetId,
    required String targetType,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/send-notification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'toUserId': toUserId,
          'type': type,
          'title': title,
          'body': body,
          'senderName': senderName,
          'senderAvatar': senderAvatar,
          'targetId': targetId,
          'targetType': targetType,
          'extraData': extraData ?? {},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send notification: ${response.body}');
      }
    } catch (e) {
      print('Error sending notification: $e');
      rethrow;
    }
  }

  // Get unread count
  Stream<int> getUnreadCount(String userId) {
    return _db
        .collection('Users')
        .doc(userId)
        .collection('Notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
