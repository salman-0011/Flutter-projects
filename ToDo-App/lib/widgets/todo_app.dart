import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';

class ToDoApp extends StatefulWidget {
  const ToDoApp({super.key});

  @override
  State<ToDoApp> createState() => _ToDoAppState();
}

class TodoItem {
  String title;
  bool isDone;
  DateTime? dueDate;
  String priority;
  List<String> tags;
  Color color;
  String? attachment;
  DateTime? reminder;
  DateTime createdAt;
  String category;
  bool isRecurring;
  String recurringType;

  TodoItem({
    required this.title,
    this.isDone = false,
    this.dueDate,
    this.priority = 'Normal',
    this.tags = const [],
    this.color = const Color(0xFFF8F9FA), // Light gray as default
    this.attachment,
    this.reminder,
    DateTime? createdAt,
    this.category = 'Personal',
    this.isRecurring = false,
    this.recurringType = 'None',
  }) : createdAt = createdAt ?? DateTime.now();
}

class _ToDoAppState extends State<ToDoApp> {
  TextEditingController todoController = TextEditingController();
  TextEditingController searchController = TextEditingController();
  DateTime? selectedDate;
  DateTime? selectedReminder;
  String selectedPriority = 'Normal';
  String selectedCategory = 'Personal';
  List<String> selectedTags = [];
  Color selectedColor = Color(0xFFF8F9FA); // Light gray as default
  String? selectedAttachment;
  bool isRecurring = false;
  String recurringType = 'None';
  List<TodoItem> todoList = [];
  TodoItem? recentlyDeleted;
  int? recentlyDeletedIndex;
  Map<String, dynamic> stats = {};
  int currentBottomNavIndex = 0;
  String filterBy = 'All';
  String sortBy = 'Created Date';
  Timer? _reminderTimer;
  Set<String> _spokenReminders = {};

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    todoController.dispose();
    searchController.dispose();
    _reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await NotificationService().initialize();
    final loadedTodos = await StorageService.loadTodos();
    final loadedStats = await StorageService.loadStats();
    setState(() {
      todoList = loadedTodos;
      stats = loadedStats;
    });
    _startReminderTimer();
  }

  Future<void> _saveTodos() async {
    await StorageService.saveTodos(todoList);
  }

  void _startReminderTimer() {
    // Check for due reminders every 30 seconds
    _reminderTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkDueReminders();
    });
  }

  void _checkDueReminders() {
    final now = DateTime.now();

    for (final todo in todoList) {
      if (todo.reminder != null && !todo.isDone) {
        // Check if reminder is due (within 1 minute tolerance)
        final timeDiff = todo.reminder!.difference(now).inSeconds.abs();
        final reminderKey =
            '${todo.title}_${todo.reminder!.millisecondsSinceEpoch}';

        if (timeDiff <= 60 && !_spokenReminders.contains(reminderKey)) {
          _spokenReminders.add(reminderKey);
          _speakReminder(todo);
          print('TTS reminder triggered for: ${todo.title}');
        }
      }
    }
  }

  Future<void> _speakReminder(TodoItem todo) async {
    await TTSService().speakTaskReminder(
      taskName: todo.title,
      dueDate: todo.dueDate,
      priority: todo.priority,
    );
  }

  Future<void> _updateStats() async {
    stats['totalCreated'] = todoList.length;
    stats['totalCompleted'] = todoList.where((todo) => todo.isDone).length;
    await StorageService.saveStats(stats);
  }

  Future<void> _pickReminder() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          selectedReminder = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _addTodo() {
    if (todoController.text.trim().isEmpty) return;
    final newTodo = TodoItem(
      title: todoController.text.trim(),
      dueDate: selectedDate,
      priority: selectedPriority,
      tags: List.from(selectedTags),
      color: selectedColor,
      attachment: selectedAttachment,
      reminder: selectedReminder,
      category: selectedCategory,
      isRecurring: isRecurring,
      recurringType: recurringType,
    );

    setState(() {
      todoList.add(newTodo);
    });

    // Schedule notification if reminder is set and in the future
    if (selectedReminder != null && selectedReminder!.isAfter(DateTime.now())) {
      NotificationService().scheduleReminderWithTTS(
        id: newTodo.hashCode,
        taskName: newTodo.title,
        scheduledTime: selectedReminder!,
        dueDate: newTodo.dueDate,
        priority: newTodo.priority,
      );
      print('Reminder with TTS scheduled for: $selectedReminder');
    } else if (selectedReminder != null) {
      print('Reminder time is in the past, not scheduling');
    }

    _saveTodos();
    _updateStats();

    // Reset form
    todoController.clear();
    selectedDate = null;
    selectedReminder = null;
    selectedPriority = 'Normal';
    selectedCategory = 'Personal';
    selectedTags = [];
    selectedColor = Color(0xFFF8F9FA);
    selectedAttachment = null;
    isRecurring = false;
    recurringType = 'None';

    Navigator.of(context).pop();
  }

  void _updateTodo(int index) {
    if (todoController.text.trim().isEmpty) return;

    setState(() {
      // Cancel old notification if reminder changed
      if (todoList[index].reminder != null) {
        NotificationService().cancelNotification(
          todoList[index].title.hashCode + todoList[index].reminder.hashCode,
        );
      }

      // Update the todo
      todoList[index] = TodoItem(
        title: todoController.text.trim(),
        isDone: todoList[index].isDone,
        category: selectedCategory,
        priority: selectedPriority,
        dueDate: selectedDate,
        reminder: selectedReminder,
        tags: selectedTags,
        color: selectedColor,
        createdAt: todoList[index].createdAt,
        isRecurring: isRecurring,
        recurringType: isRecurring ? recurringType : 'None',
      );

      // Schedule new notification if reminder is set
      if (selectedReminder != null) {
        NotificationService().scheduleReminderWithTTS(
          id: todoList[index].title.hashCode + selectedReminder.hashCode,
          taskName: todoList[index].title,
          scheduledTime: selectedReminder!,
          dueDate: selectedDate,
          priority: selectedPriority,
        );
      }
    });

    _saveTodos();
    _updateStats();

    // Reset form
    todoController.clear();
    selectedDate = null;
    selectedReminder = null;
    selectedPriority = 'Normal';
    selectedCategory = 'Personal';
    selectedTags = [];
    selectedColor = Color(0xFFF8F9FA);
    selectedAttachment = null;
    isRecurring = false;
    recurringType = 'None';

    Navigator.of(context).pop();
  }

  void _deleteTodo(int index) {
    setState(() {
      recentlyDeleted = todoList[index];
      recentlyDeletedIndex = index;
      todoList.removeAt(index);
    });
    _saveTodos();
    _updateStats();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Todo deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              if (recentlyDeleted != null && recentlyDeletedIndex != null) {
                todoList.insert(recentlyDeletedIndex!, recentlyDeleted!);
              }
            });
            _saveTodos();
            _updateStats();
          },
        ),
      ),
    );
  }

  void _toggleDone(int index) {
    setState(() {
      todoList[index].isDone = !todoList[index].isDone;
      if (todoList[index].isDone) {
        // Show celebration for completion
        NotificationService().showInstantNotification(
          id: DateTime.now().millisecondsSinceEpoch,
          title: 'Todo Completed! 🎉',
          body: 'Great job completing "${todoList[index].title}"',
        );

        // Speak completion message
        TTSService().speakTaskCompletion(todoList[index].title);

        // Handle recurring todos
        if (todoList[index].isRecurring) {
          _createRecurringTodo(todoList[index]);
        }
      }
    });
    _saveTodos();
    _updateStats();
  }

  void _createRecurringTodo(TodoItem originalTodo) {
    DateTime? nextDueDate;
    if (originalTodo.dueDate != null) {
      switch (originalTodo.recurringType) {
        case 'Daily':
          nextDueDate = originalTodo.dueDate!.add(Duration(days: 1));
          break;
        case 'Weekly':
          nextDueDate = originalTodo.dueDate!.add(Duration(days: 7));
          break;
        case 'Monthly':
          nextDueDate = DateTime(
            originalTodo.dueDate!.year,
            originalTodo.dueDate!.month + 1,
            originalTodo.dueDate!.day,
          );
          break;
      }
    }

    if (nextDueDate != null) {
      final newTodo = TodoItem(
        title: originalTodo.title,
        dueDate: nextDueDate,
        priority: originalTodo.priority,
        tags: List.from(originalTodo.tags),
        color: originalTodo.color,
        category: originalTodo.category,
        isRecurring: true,
        recurringType: originalTodo.recurringType,
      );
      setState(() {
        todoList.add(newTodo);
      });
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _showAddTodoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                "Add ToDo",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: todoController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "Enter ToDo",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Category: "),
                        DropdownButton<String>(
                          value: selectedCategory,
                          items:
                              [
                                    'Personal',
                                    'Work',
                                    'Health',
                                    'Shopping',
                                    'Other',
                                  ]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedCategory = val!;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Priority: "),
                        DropdownButton<String>(
                          value: selectedPriority,
                          items:
                              ['Low', 'Normal', 'High']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedPriority = val!;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Due Date: "),
                        Text(
                          selectedDate == null
                              ? "Not set"
                              : DateFormat(
                                'MMM dd, yyyy',
                              ).format(selectedDate!),
                        ),
                        IconButton(
                          icon: Icon(Icons.calendar_today),
                          onPressed: _pickDate,
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Reminder: "),
                        Text(
                          selectedReminder == null
                              ? "Not set"
                              : DateFormat(
                                'MMM dd, HH:mm',
                              ).format(selectedReminder!),
                        ),
                        IconButton(
                          icon: Icon(Icons.notification_add),
                          onPressed: _pickReminder,
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: isRecurring,
                          onChanged: (val) {
                            setDialogState(() {
                              isRecurring = val!;
                            });
                          },
                        ),
                        Text("Recurring"),
                        if (isRecurring) ...[
                          SizedBox(width: 10),
                          DropdownButton<String>(
                            value: recurringType,
                            items:
                                ['None', 'Daily', 'Weekly', 'Monthly']
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                recurringType = val!;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children:
                          [
                                "Work",
                                "Personal",
                                "Urgent",
                                "Home",
                                "Health",
                                "Shopping",
                              ]
                              .map(
                                (tag) => FilterChip(
                                  label: Text(tag),
                                  selected: selectedTags.contains(tag),
                                  onSelected: (selected) {
                                    setDialogState(() {
                                      if (selected) {
                                        selectedTags.add(tag);
                                      } else {
                                        selectedTags.remove(tag);
                                      }
                                    });
                                  },
                                ),
                              )
                              .toList(),
                    ),
                    SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Color: ",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Color(0xFFF8F9FA), // Light Gray
                                    Color(0xFFFEF7CD), // Soft Yellow
                                    Color(0xFFE8F5E8), // Mint Green
                                    Color(0xFFFEE2E2), // Soft Pink
                                    Color(0xFFE0F2FE), // Sky Blue
                                    Color(0xFFFEF3C7), // Warm Orange
                                    Color(0xFFF3E8FF), // Lavender
                                    Color(0xFFECFDF5), // Emerald
                                  ]
                                  .map(
                                    (c) => GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedColor = c;
                                        });
                                      },
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [c, c.withOpacity(0.8)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                selectedColor == c
                                                    ? Colors.indigo.shade600
                                                    : Colors.grey.shade300,
                                            width: selectedColor == c ? 3 : 1,
                                          ),
                                          boxShadow: [
                                            if (selectedColor == c)
                                              BoxShadow(
                                                color: Colors.indigo
                                                    .withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            BoxShadow(
                                              color: c.withOpacity(0.2),
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child:
                                            selectedColor == c
                                                ? Icon(
                                                  Icons.check,
                                                  color: Colors.indigo.shade700,
                                                  size: 18,
                                                )
                                                : null,
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Attachment: "),
                        IconButton(
                          icon: Icon(Icons.attach_file),
                          onPressed: () {
                            setDialogState(() {
                              selectedAttachment =
                                  "Document_${DateTime.now().millisecondsSinceEpoch}.pdf";
                            });
                          },
                        ),
                        if (selectedAttachment != null)
                          Expanded(
                            child: Text(
                              selectedAttachment!,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Reset form
                    selectedDate = null;
                    selectedReminder = null;
                    selectedPriority = 'Normal';
                    selectedCategory = 'Personal';
                    selectedTags = [];
                    selectedColor = Color(0xFFF8F9FA);
                    selectedAttachment = null;
                    isRecurring = false;
                    recurringType = 'None';
                  },
                  child: Text("Cancel"),
                ),
                ElevatedButton(onPressed: _addTodo, child: Text("Add")),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditTodoDialog(int index) {
    final todo = todoList[index];

    // Initialize form with current todo values
    todoController.text = todo.title;
    selectedCategory = todo.category;
    selectedPriority = todo.priority;
    selectedDate = todo.dueDate;
    selectedReminder = todo.reminder;
    selectedTags = List.from(todo.tags);
    selectedColor = todo.color;
    isRecurring = todo.isRecurring;
    recurringType = todo.recurringType;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                "Edit ToDo",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: todoController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: "Enter ToDo",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Category: "),
                        DropdownButton<String>(
                          value: selectedCategory,
                          items:
                              [
                                    'Personal',
                                    'Work',
                                    'Health',
                                    'Shopping',
                                    'Other',
                                  ]
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedCategory = val!;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Priority: "),
                        DropdownButton<String>(
                          value: selectedPriority,
                          items:
                              ['Low', 'Normal', 'High']
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedPriority = val!;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Due Date: "),
                        TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() {
                                selectedDate = date;
                              });
                            }
                          },
                          child: Text(
                            selectedDate != null
                                ? "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"
                                : "Select Date",
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text("Reminder: "),
                        TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedReminder ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(
                                  selectedReminder ?? DateTime.now(),
                                ),
                              );
                              if (time != null) {
                                setDialogState(() {
                                  selectedReminder = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    time.hour,
                                    time.minute,
                                  );
                                });
                              }
                            }
                          },
                          child: Text(
                            selectedReminder != null
                                ? "${selectedReminder!.day}/${selectedReminder!.month} ${selectedReminder!.hour}:${selectedReminder!.minute.toString().padLeft(2, '0')}"
                                : "Set Reminder",
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Color: ",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Color(0xFFF8F9FA), // Light Gray
                                    Color(0xFFFEF7CD), // Soft Yellow
                                    Color(0xFFE8F5E8), // Mint Green
                                    Color(0xFFFEE2E2), // Soft Pink
                                    Color(0xFFE0F2FE), // Sky Blue
                                    Color(0xFFFEF3C7), // Warm Orange
                                    Color(0xFFF3E8FF), // Lavender
                                    Color(0xFFECFDF5), // Emerald
                                  ]
                                  .map(
                                    (c) => GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedColor = c;
                                        });
                                      },
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [c, c.withOpacity(0.8)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color:
                                                selectedColor == c
                                                    ? Colors.indigo.shade600
                                                    : Colors.grey.shade300,
                                            width: selectedColor == c ? 3 : 1,
                                          ),
                                          boxShadow: [
                                            if (selectedColor == c)
                                              BoxShadow(
                                                color: Colors.indigo
                                                    .withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            BoxShadow(
                                              color: c.withOpacity(0.2),
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child:
                                            selectedColor == c
                                                ? Icon(
                                                  Icons.check,
                                                  color: Colors.indigo.shade700,
                                                  size: 18,
                                                )
                                                : null,
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Reset form
                    todoController.clear();
                    selectedDate = null;
                    selectedReminder = null;
                    selectedPriority = 'Normal';
                    selectedCategory = 'Personal';
                    selectedTags = [];
                    selectedColor = Color(0xFFF8F9FA);
                    selectedAttachment = null;
                    isRecurring = false;
                    recurringType = 'None';
                  },
                  child: Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => _updateTodo(index),
                  child: Text("Update"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatsView() {
    final completedToday =
        todoList
            .where(
              (todo) =>
                  todo.isDone &&
                  todo.createdAt.day == DateTime.now().day &&
                  todo.createdAt.month == DateTime.now().month &&
                  todo.createdAt.year == DateTime.now().year,
            )
            .length;

    final overdueCount =
        todoList
            .where(
              (todo) =>
                  !todo.isDone &&
                  todo.dueDate != null &&
                  todo.dueDate!.isBefore(DateTime.now()),
            )
            .length;

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Statistics",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  "Total Tasks",
                  "${stats['totalCreated'] ?? 0}",
                  Icons.list,
                  Colors.blue,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  "Completed",
                  "${stats['totalCompleted'] ?? 0}",
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  "Today",
                  "$completedToday",
                  Icons.today,
                  Colors.orange,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  "Overdue",
                  "$overdueCount",
                  Icons.warning,
                  Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Text(
            "Recent Activity",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          ...todoList
              .take(5)
              .map(
                (todo) => ListTile(
                  leading: Icon(
                    todo.isDone
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(todo.title),
                  subtitle: Text(
                    "${todo.category} • ${DateFormat('MMM dd').format(todo.createdAt)}",
                  ),
                  trailing: _getPriorityIcon(todo.priority),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _getPriorityIcon(String priority) {
    switch (priority) {
      case 'High':
        return Icon(
          Icons.keyboard_arrow_up,
          color: Colors.red.shade600,
          size: 20,
        );
      case 'Low':
        return Icon(
          Icons.keyboard_arrow_down,
          color: Colors.green.shade600,
          size: 20,
        );
      default:
        return Icon(Icons.remove, color: Colors.orange.shade600, size: 20);
    }
  }

  List<TodoItem> _getFilteredTodos() {
    List<TodoItem> filtered = todoList;

    // Apply search filter
    if (searchController.text.isNotEmpty) {
      filtered =
          filtered
              .where(
                (todo) =>
                    todo.title.toLowerCase().contains(
                      searchController.text.toLowerCase(),
                    ) ||
                    todo.tags.any(
                      (tag) => tag.toLowerCase().contains(
                        searchController.text.toLowerCase(),
                      ),
                    ),
              )
              .toList();
    }

    // Apply status filter
    switch (filterBy) {
      case 'Completed':
        filtered = filtered.where((todo) => todo.isDone).toList();
        break;
      case 'Pending':
        filtered = filtered.where((todo) => !todo.isDone).toList();
        break;
      case 'Overdue':
        filtered =
            filtered
                .where(
                  (todo) =>
                      !todo.isDone &&
                      todo.dueDate != null &&
                      todo.dueDate!.isBefore(DateTime.now()),
                )
                .toList();
        break;
    }

    // Apply sorting
    switch (sortBy) {
      case 'Priority':
        filtered.sort((a, b) {
          final priorityOrder = {'High': 3, 'Normal': 2, 'Low': 1};
          return (priorityOrder[b.priority] ?? 0).compareTo(
            priorityOrder[a.priority] ?? 0,
          );
        });
        break;
      case 'Due Date':
        filtered.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      default:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredTodos = _getFilteredTodos();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("ToDo App", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.record_voice_over),
            onPressed: () async {
              await TTSService().testSpeech();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Test speech played!')));
            },
            tooltip: 'Test Voice Reminder',
          ),
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () async {
              await NotificationService().testNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Test notification sent!')),
              );
            },
            tooltip: 'Test Notification',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value.startsWith('sort_')) {
                  sortBy = value.substring(5);
                } else {
                  filterBy = value;
                }
              });
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(value: 'All', child: Text('All Tasks')),
                  PopupMenuItem(value: 'Pending', child: Text('Pending')),
                  PopupMenuItem(value: 'Completed', child: Text('Completed')),
                  PopupMenuItem(value: 'Overdue', child: Text('Overdue')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'sort_Created Date',
                    child: Text('Sort by Date'),
                  ),
                  PopupMenuItem(
                    value: 'sort_Priority',
                    child: Text('Sort by Priority'),
                  ),
                  PopupMenuItem(
                    value: 'sort_Due Date',
                    child: Text('Sort by Due Date'),
                  ),
                ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade200, Colors.purple.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child:
            currentBottomNavIndex == 0
                ? Column(
                  children: [
                    SizedBox(height: 100), // Space for transparent app bar
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: "Search todos...",
                          prefixIcon: Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      child:
                          filteredTodos.isEmpty
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.task_alt,
                                      size: 64,
                                      color: Colors.black38,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      searchController.text.isNotEmpty
                                          ? "No matching todos!"
                                          : "No todos yet!",
                                      style: TextStyle(
                                        fontSize: 22,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : ListView.builder(
                                padding: EdgeInsets.all(8),
                                itemCount: filteredTodos.length,
                                itemBuilder: (context, index) {
                                  final todo = filteredTodos[index];
                                  final isOverdue =
                                      todo.dueDate != null &&
                                      todo.dueDate!.isBefore(DateTime.now()) &&
                                      !todo.isDone;

                                  return Dismissible(
                                    key: Key(
                                      todo.title + todo.createdAt.toString(),
                                    ),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      margin: EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        Icons.delete,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                    onDismissed: (direction) {
                                      final originalIndex = todoList.indexOf(
                                        todo,
                                      );
                                      _deleteTodo(originalIndex);
                                    },
                                    child: AnimatedContainer(
                                      duration: Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      margin: EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            todo.color,
                                            todo.color.withOpacity(0.8),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: todo.color.withOpacity(0.3),
                                            blurRadius: 12,
                                            offset: Offset(0, 6),
                                            spreadRadius: 2,
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.05,
                                            ),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                        border: Border.all(
                                          color:
                                              isOverdue
                                                  ? Colors.red.shade400
                                                  : todo.isDone
                                                  ? Colors.green.shade400
                                                  : todo.color.withOpacity(0.4),
                                          width: 2,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 8,
                                        ),
                                        leading: IconButton(
                                          icon: Icon(
                                            todo.isDone
                                                ? Icons.check_circle
                                                : Icons.radio_button_unchecked,
                                            color:
                                                todo.isDone
                                                    ? Colors.green
                                                    : Colors.grey,
                                            size: 28,
                                          ),
                                          onPressed: () {
                                            final originalIndex = todoList
                                                .indexOf(todo);
                                            _toggleDone(originalIndex);
                                          },
                                        ),
                                        title: Text(
                                          todo.title,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                todo.isDone
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                            color:
                                                todo.isDone
                                                    ? Colors.grey.shade600
                                                    : Colors.grey.shade800,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (todo.dueDate != null)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.calendar_today,
                                                    size: 16,
                                                    color:
                                                        isOverdue
                                                            ? Colors.red
                                                            : Colors.deepPurple,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      "Due: ${DateFormat('MMM dd, yyyy').format(todo.dueDate!)}",
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            isOverdue
                                                                ? Colors
                                                                    .red
                                                                    .shade600
                                                                : Colors
                                                                    .deepPurple
                                                                    .shade600,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (todo.reminder != null)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.notification_add,
                                                    size: 16,
                                                    color: Colors.orange,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      "Reminder: ${DateFormat('MMM dd, HH:mm').format(todo.reminder!)}",
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            Colors
                                                                .orange
                                                                .shade600,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    "${todo.category} • ",
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          Colors
                                                              .blueGrey
                                                              .shade600,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                _getPriorityIcon(todo.priority),
                                                Text(
                                                  " ${todo.priority}",
                                                  style: TextStyle(
                                                    color:
                                                        Colors
                                                            .blueGrey
                                                            .shade600,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (todo.isRecurring) ...[
                                                  SizedBox(width: 8),
                                                  Icon(
                                                    Icons.repeat,
                                                    size: 16,
                                                    color: Colors.purple,
                                                  ),
                                                  Text(
                                                    " ${todo.recurringType}",
                                                    style: TextStyle(
                                                      color: Colors.purple,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (todo.tags.isNotEmpty)
                                              Wrap(
                                                spacing: 6,
                                                children:
                                                    todo.tags
                                                        .map(
                                                          (tag) => Chip(
                                                            label: Text(
                                                              tag,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    Colors
                                                                        .indigo
                                                                        .shade700,
                                                              ),
                                                            ),
                                                            backgroundColor:
                                                                Colors
                                                                    .indigo
                                                                    .shade50,
                                                            side: BorderSide(
                                                              color:
                                                                  Colors
                                                                      .indigo
                                                                      .shade200,
                                                              width: 1,
                                                            ),
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                          ),
                                                        )
                                                        .toList(),
                                              ),
                                            if (todo.attachment != null)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.attach_file,
                                                    size: 16,
                                                  ),
                                                  Text(
                                                    todo.attachment!,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.volume_up,
                                                color: Colors.orange.shade600,
                                              ),
                                              onPressed: () async {
                                                await TTSService()
                                                    .speakTaskReminder(
                                                      taskName: todo.title,
                                                      dueDate: todo.dueDate,
                                                      priority: todo.priority,
                                                    );
                                              },
                                              tooltip: 'Speak Reminder',
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: Colors.blueAccent,
                                              ),
                                              onPressed: () {
                                                final originalIndex = todoList
                                                    .indexOf(todo);
                                                _showEditTodoDialog(
                                                  originalIndex,
                                                );
                                              },
                                              tooltip: 'Edit Todo',
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete,
                                                color: Colors.red.shade600,
                                              ),
                                              onPressed: () {
                                                final originalIndex = todoList
                                                    .indexOf(todo);
                                                _deleteTodo(originalIndex);
                                              },
                                              tooltip: 'Delete Todo',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                    ),
                  ],
                )
                : _buildStatsView(),
      ),
      floatingActionButton:
          currentBottomNavIndex == 0
              ? FloatingActionButton.extended(
                onPressed: _showAddTodoDialog,
                label: Text("Add Todo"),
                icon: Icon(Icons.add),
                backgroundColor: Colors.purple,
              )
              : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentBottomNavIndex,
        onTap: (index) {
          setState(() {
            currentBottomNavIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.list), label: "Todos"),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: "Stats"),
        ],
      ),
    );
  }
}
