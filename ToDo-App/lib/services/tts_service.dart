import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isTTSAvailable = true;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Test if TTS is available by checking if we can set language
      await _flutterTts.setLanguage("en-US");

      // Configure TTS settings
      await _flutterTts.setSpeechRate(0.5); // Moderate speed
      await _flutterTts.setVolume(0.8); // 80% volume
      await _flutterTts.setPitch(1.0); // Normal pitch

      // Set TTS engine to use system default
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _flutterTts.setEngine("com.google.android.tts");
        } catch (e) {
          // If Google TTS is not available, continue with default
          if (kDebugMode) {
            print('Google TTS not available, using default: $e');
          }
        }
      }

      _isInitialized = true;
      _isTTSAvailable = true;

      if (kDebugMode) {
        print('TTS Service initialized successfully');
      }
    } catch (e) {
      _isTTSAvailable = false;
      if (kDebugMode) {
        print('Error initializing TTS: $e');
        print('TTS will be disabled for this session');
      }
    }
  }

  Future<void> speakTaskReminder({
    required String taskName,
    DateTime? dueDate,
    String priority = 'Normal',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isTTSAvailable) {
      if (kDebugMode) {
        print('TTS not available - showing text message instead');
        String message = _buildReminderMessage(taskName, dueDate, priority);
        print('Reminder Message: $message');
      }
      return;
    }

    try {
      String message = _buildReminderMessage(taskName, dueDate, priority);

      if (kDebugMode) {
        print('Speaking: $message');
      }

      await _flutterTts.speak(message);
    } catch (e) {
      if (e is MissingPluginException) {
        _isTTSAvailable = false;
        if (kDebugMode) {
          print('TTS plugin not found - disabling TTS for this session');
        }
      } else {
        if (kDebugMode) {
          print('Error speaking reminder: $e');
        }
      }
    }
  }

  String _buildReminderMessage(
    String taskName,
    DateTime? dueDate,
    String priority,
  ) {
    String message = "Reminder! Your task '$taskName' is still pending.";

    if (dueDate != null) {
      final now = DateTime.now();
      final difference = dueDate.difference(now);

      if (difference.isNegative) {
        // Overdue
        final overdueDays = difference.inDays.abs();
        if (overdueDays == 0) {
          message += " It was due today.";
        } else if (overdueDays == 1) {
          message += " It was due yesterday.";
        } else {
          message += " It was due $overdueDays days ago.";
        }
      } else if (difference.inDays == 0) {
        // Due today
        message += " It's due today.";
      } else if (difference.inDays == 1) {
        // Due tomorrow
        message += " It's due tomorrow.";
      } else {
        // Due in future
        message += " It's due on ${DateFormat('MMMM dd').format(dueDate)}.";
      }
    }

    if (priority == 'High') {
      message += " This is a high priority task.";
    } else if (priority == 'Low') {
      message += " This is a low priority task.";
    }

    message += " Please complete it when you get a chance.";

    return message;
  }

  Future<void> speakTaskCompletion(String taskName) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isTTSAvailable) {
      if (kDebugMode) {
        print('TTS not available - showing completion message instead');
        print(
          'Completion Message: Congratulations! You have completed the task \'$taskName\'. Great job!',
        );
      }
      return;
    }

    try {
      String message =
          "Congratulations! You have completed the task '$taskName'. Great job!";

      if (kDebugMode) {
        print('Speaking completion: $message');
      }

      await _flutterTts.speak(message);
    } catch (e) {
      if (e is MissingPluginException) {
        _isTTSAvailable = false;
        if (kDebugMode) {
          print('TTS plugin not found - disabling TTS for this session');
        }
      } else {
        if (kDebugMode) {
          print('Error speaking completion: $e');
        }
      }
    }
  }

  Future<void> testSpeech() async {
    await speakTaskReminder(
      taskName: "Test Task",
      dueDate: DateTime.now().add(Duration(days: 1)),
      priority: "High",
    );
  }

  Future<void> stop() async {
    if (!_isTTSAvailable) return;

    try {
      await _flutterTts.stop();
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping TTS: $e');
      }
    }
  }

  Future<void> pause() async {
    if (!_isTTSAvailable) return;

    try {
      await _flutterTts.pause();
    } catch (e) {
      if (kDebugMode) {
        print('Error pausing TTS: $e');
      }
    }
  }

  // Add method to check if TTS is available
  bool get isAvailable => _isTTSAvailable && _isInitialized;
}
