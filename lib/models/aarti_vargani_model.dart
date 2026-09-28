class AartiVargani {
  final int? id;
  final String name;
  final double amount;
  final int year;

  AartiVargani({
    this.id,
    required this.name,
    required this.amount,
    required this.year,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'year': year,
    };
  }

  factory AartiVargani.fromMap(Map<String, dynamic> map) {
    return AartiVargani(
      id: map['id'],
      name: map['name'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      year: map['year'] ?? DateTime.now().year,
    );
  }
}