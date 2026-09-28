class Vargani {
  final int? id;
  final String name;
  final double amount;
  final int year;

  Vargani({
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

  factory Vargani.fromMap(Map<String, dynamic> map) {
    return Vargani(
      id: map['id'],
      name: map['name'],
      amount: (map['amount'] as num).toDouble(),
      year: map['year'],
    );
  }
}