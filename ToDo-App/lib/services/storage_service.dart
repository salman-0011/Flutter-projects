import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/todo_app.dart';
import 'package:flutter/material.dart';

class StorageService {
  static const String _todoKey = 'todos';
  static const String _statsKey = 'stats';

  static Future<void> saveTodos(List<TodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> todoMaps =
        todos.map((todo) {
          return {
            'title': todo.title,
            'isDone': todo.isDone,
            'dueDate': todo.dueDate?.toIso8601String(),
            'priority': todo.priority,
            'tags': todo.tags,
            'color': todo.color.value,
            'attachment': todo.attachment,
            'reminder': todo.reminder?.toIso8601String(),
            'createdAt': todo.createdAt.toIso8601String(),
            'category': todo.category,
            'isRecurring': todo.isRecurring,
            'recurringType': todo.recurringType,
          };
        }).toList();

    await prefs.setString(_todoKey, jsonEncode(todoMaps));
  }

  static Future<List<TodoItem>> loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? todosJson = prefs.getString(_todoKey);

    if (todosJson == null) return [];

    final List<dynamic> todoMaps = jsonDecode(todosJson);
    return todoMaps.map((map) {
      return TodoItem(
        title: map['title'],
        isDone: map['isDone'] ?? false,
        dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
        priority: map['priority'] ?? 'Normal',
        tags: List<String>.from(map['tags'] ?? []),
        color: Color(map['color'] ?? Colors.white.value),
        attachment: map['attachment'],
        reminder:
            map['reminder'] != null ? DateTime.parse(map['reminder']) : null,
        createdAt:
            map['createdAt'] != null
                ? DateTime.parse(map['createdAt'])
                : DateTime.now(),
        category: map['category'] ?? 'Personal',
        isRecurring: map['isRecurring'] ?? false,
        recurringType: map['recurringType'] ?? 'None',
      );
    }).toList();
  }

  static Future<void> saveStats(Map<String, dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statsKey, jsonEncode(stats));
  }

  static Future<Map<String, dynamic>> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final String? statsJson = prefs.getString(_statsKey);

    if (statsJson == null) {
      return {
        'totalCompleted': 0,
        'totalCreated': 0,
        'streak': 0,
        'lastCompletedDate': null,
      };
    }

    return jsonDecode(statsJson);
  }
}
