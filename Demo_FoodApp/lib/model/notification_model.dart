import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class NotificationModel {
  static List<Map<String, dynamic>> notifications = [];
  static final ValueNotifier<int> refreshSignal = ValueNotifier(0);

  static Future<void> fetchNotifications(String userId) async {
    try {
      notifications = await ApiService.getNotifications(userId);
      refreshSignal.value++;
    } catch (e) {
      notifications = [];
      rethrow;
    }
  }

  static Future<void> markAsRead(String notificationId) async {
    try {
      await ApiService.markNotificationAsRead(notificationId);
      // Update local list
      final index = notifications.indexWhere((n) => n['_id'] == notificationId);
      if (index != -1) {
        notifications[index]['isRead'] = true;
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    try {
      await ApiService.deleteNotification(notificationId);
      // Remove from local list
      notifications.removeWhere((n) => n['_id'] == notificationId);
    } catch (e) {
      rethrow;
    }
  }
}