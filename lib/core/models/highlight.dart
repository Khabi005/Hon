class Highlight {
  final String id;
  final String bookId;
  final String locatorString;
  final String selectedText;
  final String color;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Highlight({
    required this.id,
    required this.bookId,
    required this.locatorString,
    required this.selectedText,
    this.color = 'yellow',
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  Highlight copyWith({
    String? id,
    String? bookId,
    String? locatorString,
    String? selectedText,
    String? color,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Highlight(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      locatorString: locatorString ?? this.locatorString,
      selectedText: selectedText ?? this.selectedText,
      color: color ?? this.color,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'bookId': bookId,
    'locatorString': locatorString,
    'selectedText': selectedText,
    'color': color,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Highlight.fromMap(Map<String, dynamic> map) {
    return Highlight(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      locatorString: map['locatorString'] as String,
      selectedText: map['selectedText'] as String,
      color: (map['color'] as String?) ?? 'yellow',
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
