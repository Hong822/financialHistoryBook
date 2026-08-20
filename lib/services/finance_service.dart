import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:http/http.dart' as http;
import '../models/stock_model.dart';

class FinanceService {
  static const String _searchBaseUrl = 'https://query2.finance.yahoo.com/v1/finance/search';
  static const String _chartBaseUrl = 'https://query1.finance.yahoo.com/v8/finance/chart';

  static String _proxy(String url) =>
      kIsWeb ? 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}' : url;

  static Map<String, String> get _headers => kIsWeb ? {} : {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  String lastFetchedCurrency = 'USD';

  Future<List<dynamic>> searchStocks(String query) async {
    final url = Uri.parse(_proxy('$_searchBaseUrl?q=$query'));
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return json.decode(response.body)['quotes'] ?? [];
      }
    } catch (e) {
      debugPrint('Search API Error: $e');
    }
    return [];
  }

  Future<List<StockDataPoint>> fetchStockData({
    required String symbol,
    required String period,
    DateTimeRange? customRange,
  }) async {
    String range = period;
    String interval = '1d';
    int? start;
    int? end;

    if (period == 'custom' && customRange != null) {
      start = customRange.start.millisecondsSinceEpoch ~/ 1000;
      end = customRange.end.millisecondsSinceEpoch ~/ 1000;
      interval = '1d';
    } else {
      // 10y, 20y(max) 등에 대해서는 간격 조정이 필요할 수 있음
      if (range == '10y' || range == 'max') interval = '1wk';
    }

    final data = await fetchChartData(symbol, range: range, interval: interval, start: start, end: end);
    if (data == null) return [];

    lastFetchedCurrency = data['meta']['currency'] ?? 'USD';
    
    final timestamps = List<int>.from(data['timestamp']);
    final indicators = data['indicators']['quote'][0];
    final closes = List<double?>.from(indicators['close']);

    List<StockDataPoint> points = [];
    for (int i = 0; i < timestamps.length; i++) {
      if (closes[i] != null) {
        points.add(StockDataPoint(
          DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000),
          closes[i]!,
        ));
      }
    }
    return points;
  }

  Future<Map<String, dynamic>?> fetchChartData(String symbol, {String? range, String? interval, int? start, int? end}) async {
    String urlStr;
    if (start != null && end != null) {
      urlStr = '$_chartBaseUrl/$symbol?period1=$start&period2=$end&interval=$interval';
    } else {
      urlStr = '$_chartBaseUrl/$symbol?range=$range&interval=$interval';
    }
    
    final url = Uri.parse(_proxy(urlStr));
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return json.decode(response.body)['chart']['result'][0];
      }
    } catch (e) {
      debugPrint('Chart API Error ($symbol): $e');
    }
    return null;
  }
}
