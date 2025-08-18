import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final bool? initialized = await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTapped,
    );

    if (kDebugMode) {
      print('Notification service initialized: $initialized');
    }

    await _requestPermissions();
    await _createNotificationChannel();
    await TTSService().initialize();
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'todo_channel',
      'Todo Reminders',
      description: 'Notifications for todo reminders',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }
    _handleNotificationResponse(response);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Background notification tapped: ${response.payload}');
    }
    _handleNotificationResponse(response);
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        final String taskName = data['taskName'] ?? 'Unknown Task';
        final String? dueDateStr = data['dueDate'];
        final String priority = data['priority'] ?? 'Normal';

        DateTime? dueDate;
        if (dueDateStr != null) {
          dueDate = DateTime.parse(dueDateStr);
        }

        // Speak the reminder when notification is tapped
        TTSService().speakTaskReminder(
          taskName: taskName,
          dueDate: dueDate,
          priority: priority,
        );
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing notification payload: $e');
        }
      }
    }
  }

  Future<void> _requestPermissions() async {
    // Request notification permission for Android 13+
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Request exact alarm permission for Android 12+
    try {
      if (await Permission.scheduleExactAlarm.isDenied) {
        final status = await Permission.scheduleExactAlarm.request();
        if (kDebugMode) {
          print('Exact alarm permission status: $status');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting exact alarm permission: $e');
        print('Will use inexact alarms instead');
      }
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? taskName,
    DateTime? dueDate,
    String priority = 'Normal',
  }) async {
    try {
      if (kDebugMode) {
        print('Scheduling notification for: $scheduledTime');
        print('Current time: ${DateTime.now()}');
      }

      // Create payload with task details for TTS
      final Map<String, dynamic> payload = {
        'taskName': taskName ?? body,
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority,
      };

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'todo_channel',
            'Todo Reminders',
            channelDescription: 'Notifications for todo reminders',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            autoCancel: false,
            ongoing: false,
            enableVibration: true,
            playSound: true,
            actions: [
              AndroidNotificationAction(
                'speak_action',
                'Speak Reminder',
                showsUserInterface: false,
              ),
              AndroidNotificationAction(
                'complete_action',
                'Mark Complete',
                showsUserInterface: false,
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(payload),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      if (kDebugMode) {
        print('Reminder with TTS scheduled for: $scheduledTime');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scheduling notification: $e');
      }

      // If exact alarm fails, try with inexact alarm
      if (e.toString().contains('exact_alarms_not_permitted')) {
        try {
          if (kDebugMode) {
            print('Retrying with inexact alarm...');
          }

          // Recreate payload for fallback
          final Map<String, dynamic> fallbackPayload = {
            'taskName': taskName ?? body,
            'dueDate': dueDate?.toIso8601String(),
            'priority': priority,
          };

          await _notifications.zonedSchedule(
            id,
            title,
            body,
            tz.TZDateTime.from(scheduledTime, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'todo_channel',
                'Todo Reminders',
                channelDescription: 'Notifications for todo reminders',
                importance: Importance.high,
                priority: Priority.high,
                showWhen: true,
                autoCancel: false,
                ongoing: false,
                enableVibration: true,
                playSound: true,
                actions: [
                  AndroidNotificationAction(
                    'speak_action',
                    'Speak Reminder',
                    showsUserInterface: false,
                  ),
                  AndroidNotificationAction(
                    'complete_action',
                    'Mark Complete',
                    showsUserInterface: false,
                  ),
                ],
              ),
              iOS: DarwinNotificationDetails(),
            ),
            payload: jsonEncode(fallbackPayload),
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
            androidScheduleMode: AndroidScheduleMode.inexact,
          );

          if (kDebugMode) {
            print('Inexact notification scheduled successfully with ID: $id');
          }
        } catch (fallbackError) {
          if (kDebugMode) {
            print('Fallback scheduling also failed: $fallbackError');
          }
        }
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      if (kDebugMode) {
        print('Showing instant notification: $title');
      }

      await _notifications.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'todo_channel',
            'Todo Reminders',
            channelDescription: 'Notifications for todo reminders',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

      if (kDebugMode) {
        print('Instant notification shown successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error showing instant notification: $e');
      }
    }
  }

  Future<void> testNotification() async {
    await showInstantNotification(
      id: 999,
      title: 'Test Notification',
      body: 'This is a test to check if notifications are working!',
    );
  }

  Future<void> scheduleReminderWithTTS({
    required int id,
    required String taskName,
    required DateTime scheduledTime,
    DateTime? dueDate,
    String priority = 'Normal',
  }) async {
    // Schedule the notification
    await scheduleNotification(
      id: id,
      title: '🔔 Todo Reminder',
      body: taskName,
      scheduledTime: scheduledTime,
      taskName: taskName,
      dueDate: dueDate,
      priority: priority,
    );

    // For immediate testing (when scheduled time is very close)
    final timeDifference = scheduledTime.difference(DateTime.now());
    if (timeDifference.inSeconds <= 5 && timeDifference.inSeconds > 0) {
      // If scheduled for within 5 seconds, also prepare TTS
      Future.delayed(timeDifference, () {
        TTSService().speakTaskReminder(
          taskName: taskName,
          dueDate: dueDate,
          priority: priority,
        );
      });
    }
  }

  Future<void> speakTaskNow({
    required String taskName,
    DateTime? dueDate,
    String priority = 'Normal',
  }) async {
    await TTSService().speakTaskReminder(
      taskName: taskName,
      dueDate: dueDate,
      priority: priority,
    );
  }
}
