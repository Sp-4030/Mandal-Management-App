class PrasadSahitya {
  final int? id;
  final String name;
  final String item;
  final int year;

  PrasadSahitya({
    this.id,
    required this.name,
    required this.item,
    required this.year,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'item': item,
      'year': year,
    };
  }

  factory PrasadSahitya.fromMap(Map<String, dynamic> map) {
    return PrasadSahitya(
      id: map['id'],
      name: map['name'] ?? '',
      item: map['item'] ?? '',
      year: map['year'] ?? DateTime.now().year,
    );
  }
}