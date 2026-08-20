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
}

class StockDataPoint {
  final DateTime date;
  final double price;

  StockDataPoint(this.date, this.price);
}
