import 'package:flutter/material.dart';

class Stock {
  final String name;
  final String symbol;
  final String? type;
  final String? exchange;
  final Color color;

  Stock({
    required this.name,
    required this.symbol,
    this.type,
    this.exchange,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'symbol': symbol,
    'type': type,
    'exchange': exchange,
    'color': color.value,
  };

  factory Stock.fromJson(Map<String, dynamic> json) => Stock(
    name: json['name'],
    symbol: json['symbol'],
    type: json['type'],
    exchange: json['exchange'],
    color: Color(json['color']),
  );
}

class StockDataPoint {
  final DateTime date;
  final double price;

  StockDataPoint(this.date, this.price);
}
