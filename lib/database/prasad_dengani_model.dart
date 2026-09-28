class PrasadDengani {
  final int? id;
  final String name;
  final double amount;
  final int year;

  PrasadDengani({
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

  factory PrasadDengani.fromMap(Map<String, dynamic> map) {
    return PrasadDengani(
      id: map['id'] as int?,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      year: map['year'] as int,
    );
  }
}