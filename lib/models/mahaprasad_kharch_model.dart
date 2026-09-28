class MahaprasadKharch {
  final int? id;
  final String item;
  final String buyerName;
  final double amount;
  final int year;

  MahaprasadKharch({
    this.id,
    required this.item,
    required this.buyerName,
    required this.amount,
    required this.year,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item': item,
      'buyer_name': buyerName,
      'amount': amount,
      'year': year,
    };
  }

  factory MahaprasadKharch.fromMap(Map<String, dynamic> map) {
    return MahaprasadKharch(
      id: map['id'],
      item: map['item'] ?? '',
      buyerName: map['buyer_name'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      year: map['year'] ?? DateTime.now().year,
    );
  }
}