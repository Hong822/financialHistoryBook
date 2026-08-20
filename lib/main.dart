import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:async';

import 'models/stock_model.dart';
import 'services/finance_service.dart';

void main() {
  runApp(const FinancialHistoryApp());
}

class FinancialHistoryApp extends StatelessWidget {
  const FinancialHistoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '금융 히스토리',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const StockChartPage(),
    );
  }
}

class StockChartPage extends StatefulWidget {
  const StockChartPage({super.key});

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage> {
  final FinanceService _financeService = FinanceService();
  final List<TextEditingController> _searchControllers = List.generate(5, (_) => TextEditingController());
  final List<Stock?> _selectedSlotStocks = List.generate(5, (_) => null);
  final List<List<Stock>> _searchResultSlots = List.generate(5, (_) => []);
  final List<Timer?> _debounceTimers = List.generate(5, (_) => null);
  final List<bool> _slotSearching = List.generate(5, (_) => false);
  final Map<String, List<StockDataPoint>> _stockDataCache = {};
  int _visibleSlotsCount = 1;
  bool _isFavExpanded = false;
  bool _isSearchExpanded = false;

  final List<Stock?> _userFavorites = List.generate(6, (_) => null);

  final List<Color> _chartPalette = [
    const Color(0xFFFFAB45), const Color(0xFF209AA1), const Color(0xFFFF7651), const Color(0xFF75BF8A), const Color(0xFF225075),
  ];

  bool _isLoading = false;
  final List<String> _logs = [];

  String _selectedPeriod = '1년';
  DateTimeRange? _customDateRange;
  final Map<String, String> _periodMap = {
    '1개월': '1mo', '6개월': '6mo', '1년': '1y', '3년': '3y', '5년': '5y', '10년': '10y', '20년': 'max', '기간 선택': 'custom',
  };

  String _selectedUnit = '월';
  final List<String> _units = ['일', '주', '월', '년'];

  String _selectedCurrency = '달러';
  final List<String> _currencies = ['달러', '원화', '유로'];
  final Map<String, String> _stockOriginalCurrency = {};

  final Map<String, double> _toUsdRates = {'USD': 1.0, 'KRW': 1 / 1350.0, 'EUR': 1 / 0.92};
  final Map<String, double> _fromUsdRates = {'달러': 1.0, '원화': 1350.0, '유로': 0.92};

  @override
  void initState() {
    super.initState();
    _addLog('앱 시작. 검색 버튼을 눌러 종목을 추가하세요.');
  }

  void _addLog(String message) {
    final now = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() => _logs.insert(0, '[$now] $message'));
    if (_logs.length > 50) _logs.removeLast();
  }

  @override
  void dispose() {
    for (var timer in _debounceTimers) timer?.cancel();
    for (var controller in _searchControllers) controller.dispose();
    super.dispose();
  }

  // --- 비즈니스 로직 (FinanceService 연동) ---
  Future<void> _searchStock(int index, String query, StateSetter setModalState) async {
    if (query.length < 2) {
      setModalState(() => _searchResultSlots[index] = []);
      return;
    }
    setModalState(() => _slotSearching[index] = true);
    final results = await _financeService.searchStocks(query);
    setModalState(() {
      _searchResultSlots[index] = results.map((q) => Stock(
        name: q['shortname'] ?? q['longname'] ?? q['symbol'],
        symbol: q['symbol'],
        type: q['quoteType'],
        exchange: q['exchDisp'],
        color: _chartPalette[index % _chartPalette.length],
      )).toList();
      _slotSearching[index] = false;
    });
  }

  Future<void> _updateStockData(Stock stock) async {
    setState(() => _isLoading = true);
    _addLog('데이터 요청: ${stock.symbol} (${_selectedPeriod})');
    try {
      final data = await _financeService.fetchStockData(
        symbol: stock.symbol,
        period: _periodMap[_selectedPeriod]!,
        customRange: _customDateRange,
      );
      setState(() {
        _stockDataCache[stock.symbol] = data;
        _stockOriginalCurrency[stock.symbol] = _financeService.lastFetchedCurrency;
      });
      _addLog('데이터 수신 완료: ${stock.symbol} (${data.length}건)');
    } catch (e) {
      _addLog('데이터 오류: ${stock.symbol} - $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDataForAll() async {
    final activeStocks = _selectedSlotStocks.whereType<Stock>().toList();
    if (activeStocks.isEmpty) return;
    for (var s in activeStocks) {
      await _updateStockData(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주가 히스토리', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCompactSettingBar(),
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: _selectedSlotStocks.whereType<Stock>().isEmpty 
                  ? const Center(child: Text('검색 버튼을 눌러 종목을 추가하세요.'))
                  : _buildChart(),
              ),
            ),
            _buildLegend(),
            const SizedBox(height: 16),
            _buildCollapsibleLog(),
          ],
        ),
      ),
    );
  }

  // 차트 위에 작게 표시되는 설정 바
  Widget _buildCompactSettingBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildSettingChip(
            label: '검색/비교',
            icon: Icons.search,
            onTap: _showSearchBottomSheet,
            isPrimary: true,
          ),
          const SizedBox(width: 8),
          _buildSettingChip(label: _selectedPeriod, icon: Icons.calendar_today, onTap: _showPeriodPicker),
          const SizedBox(width: 8),
          _buildSettingChip(label: _selectedUnit, icon: Icons.bar_chart, onTap: _showUnitPicker),
          const SizedBox(width: 8),
          _buildSettingChip(label: _selectedCurrency, icon: Icons.attach_money, onTap: _showCurrencyPicker),
        ],
      ),
    );
  }

  Widget _buildSettingChip({required String label, required IconData icon, required VoidCallback onTap, bool isPrimary = false}) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: isPrimary ? Colors.white : Colors.blue),
      label: Text(label, style: TextStyle(color: isPrimary ? Colors.white : Colors.black87, fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal)),
      backgroundColor: isPrimary ? Colors.blue : Colors.grey.shade100,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  void _showFavoriteSearch(int favIndex, StateSetter parentSetModalState) {
    final controller = TextEditingController();
    List<Stock> results = [];
    bool isSearching = false;
    Timer? debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('즐겨찾기 종목 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 500), () async {
                    if (v.length < 2) return;
                    setModalState(() => isSearching = true);
                    final raw = await _financeService.searchStocks(v);
                    setModalState(() {
                      results = raw.map((q) => Stock(
                        name: q['shortname'] ?? q['longname'] ?? q['symbol'],
                        symbol: q['symbol'],
                        type: q['quoteType'],
                        exchange: q['exchDisp'],
                        color: Colors.grey,
                      )).toList();
                      isSearching = false;
                    });
                  });
                },
                decoration: const InputDecoration(hintText: '종목명 또는 심볼 검색', prefixIcon: Icon(Icons.search)),
              ),
              if (isSearching) const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()),
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(results[i].symbol),
                    subtitle: Text(results[i].name),
                    onTap: () {
                      setState(() => _userFavorites[favIndex] = results[i]);
                      parentSetModalState(() {});
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addStockFromFavorite(Stock fav, StateSetter setModalState) {
    if (_selectedSlotStocks.any((s) => s?.symbol == fav.symbol)) return;

    int targetIndex = -1;
    for (int i = 0; i < _visibleSlotsCount; i++) {
      if (_selectedSlotStocks[i] == null) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == -1 && _visibleSlotsCount < 5) {
      targetIndex = _visibleSlotsCount;
      setModalState(() => _visibleSlotsCount++);
    }
    if (targetIndex != -1) {
      final stockWithColor = Stock(
        symbol: fav.symbol,
        name: fav.name,
        type: fav.type,
        exchange: fav.exchange,
        color: _chartPalette[targetIndex % _chartPalette.length],
      );
      setState(() => _selectedSlotStocks[targetIndex] = stockWithColor);
      setModalState(() {});
      _updateStockData(stockWithColor);
    }
  }

  void _showSearchBottomSheet() {
    int lastOccupied = -1;
    for (int i = 0; i < 5; i++) {
      if (_selectedSlotStocks[i] != null) lastOccupied = i;
    }
    if (lastOccupied + 1 > _visibleSlotsCount) {
      _visibleSlotsCount = lastOccupied + 1;
    }

    // 메뉴에 들어올 때 기본적으로 접혀있도록 설정
    _isFavExpanded = false;
    _isSearchExpanded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  
                  // 즐겨찾기 섹션 헤더
                  InkWell(
                    onTap: () => setModalState(() => _isFavExpanded = !_isFavExpanded),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('즐겨찾기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                        Icon(_isFavExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.blueGrey),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  if (_isFavExpanded)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 2.5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        final fav = _userFavorites[index];
                        return GestureDetector(
                          onLongPress: fav == null ? null : () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('즐겨찾기 해제'),
                                content: Text('${fav.name} 종목을 즐겨찾기에서 해제하시겠습니까?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _userFavorites[index] = null);
                                      setModalState(() {});
                                      Navigator.pop(ctx);
                                    }, 
                                    child: const Text('해제', style: TextStyle(color: Colors.red))
                                  ),
                                ],
                              ),
                            );
                          },
                          child: ActionChip(
                            padding: EdgeInsets.zero,
                            avatar: fav == null ? const Icon(Icons.add, size: 16) : null,
                            label: Center(child: Text(fav?.symbol ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            onPressed: () {
                              if (fav == null) {
                                _showFavoriteSearch(index, setModalState);
                              } else {
                                _addStockFromFavorite(fav, setModalState);
                              }
                            },
                            backgroundColor: fav == null ? Colors.grey.shade100 : Colors.blue.shade50,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),

                  // 종목 검색 섹션 헤더
                  InkWell(
                    onTap: () => setModalState(() => _isSearchExpanded = !_isSearchExpanded),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('종목 비교 검색', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                        Icon(_isSearchExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.blueGrey),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  if (_isSearchExpanded)
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _visibleSlotsCount + (_visibleSlotsCount < 5 ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i < _visibleSlotsCount) {
                            return _buildSearchSlotInModal(i, setModalState);
                          } else {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: TextButton.icon(
                                onPressed: () => setModalState(() => _visibleSlotsCount++),
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('종목 추가하기'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSlotInModal(int index, StateSetter setModalState) {
    final stock = _selectedSlotStocks[index];
    return Column(
      children: [
        TextField(
          controller: _searchControllers[index],
          onChanged: (v) {
            _debounceTimers[index]?.cancel();
            _debounceTimers[index] = Timer(const Duration(milliseconds: 500), () => _searchStock(index, v, setModalState));
          },
          decoration: InputDecoration(
            hintText: stock != null ? '${stock.name} (${stock.symbol})' : '종목 입력',
            prefixIcon: stock != null ? Icon(Icons.check_circle, color: stock.color) : const Icon(Icons.add),
            suffixIcon: (stock != null || _searchControllers[index].text.isNotEmpty) 
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() {
                  _selectedSlotStocks[index] = null;
                  _searchControllers[index].clear();
                  _searchResultSlots[index] = [];
                  setModalState((){});
                })) : null,
          ),
        ),
        if (_searchResultSlots[index].isNotEmpty)
          ..._searchResultSlots[index].map((s) => ListTile(
            dense: true,
            title: Row(
              children: [
                _buildExchangeBadge(s),
                const SizedBox(width: 8),
                Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            subtitle: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(s.type ?? '', style: const TextStyle(fontSize: 10)),
                Text(s.exchange ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            onTap: () {
              setState(() {
                _selectedSlotStocks[index] = s;
                _searchResultSlots[index] = [];
                _searchControllers[index].clear();
              });
              setModalState((){ _searchResultSlots[index] = []; });
              _updateStockData(s);
            },
          )),
        const SizedBox(height: 12),
      ],
    );
  }

  // 각종 설정 Picker 메서드들
  void _showPeriodPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: _periodMap.keys.map((p) => ListTile(
            title: Text(p),
            onTap: () {
              Navigator.pop(context);
              if (p == '기간 선택') {
                _showCustomDateRangePicker();
              } else {
                setState(() => _selectedPeriod = p);
                _fetchDataForAll();
              }
            },
            trailing: _selectedPeriod == p ? const Icon(Icons.check, color: Colors.blue) : null,
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _showCustomDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = '기간 선택';
        _customDateRange = picked;
      });
      _fetchDataForAll();
    }
  }

  void _showUnitPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: _units.map((u) => ListTile(
            title: Text(u),
            onTap: () {
              setState(() => _selectedUnit = u);
              Navigator.pop(context);
            },
            trailing: _selectedUnit == u ? const Icon(Icons.check, color: Colors.blue) : null,
          )).toList(),
        ),
      ),
    );
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: _currencies.map((c) => ListTile(
            title: Text(c),
            onTap: () {
              setState(() => _selectedCurrency = c);
              Navigator.pop(context);
            },
            trailing: _selectedCurrency == c ? const Icon(Icons.check, color: Colors.blue) : null,
          )).toList(),
        ),
      ),
    );
  }

  // --- 차트 및 UI 렌더링 ---
  Widget _buildChart() {
    final activeStocks = _selectedSlotStocks.whereType<Stock>().toList();
    if (activeStocks.isEmpty) return const SizedBox.shrink();

    // 데이터가 하나라도 로딩되지 않았다면 안내 메시지
    if (activeStocks.any((s) => !_stockDataCache.containsKey(s.symbol))) {
      return const Center(child: CircularProgressIndicator());
    }

    return LineChart(_generateChartData(activeStocks));
  }

  LineChartData _generateChartData(List<Stock> stocks) {
    List<LineChartBarData> lineBarsData = [];
    double minX = double.maxFinite;
    double maxX = double.minPositive;
    double minY = double.maxFinite;
    double maxY = 0;

    for (var stock in stocks) {
      final dataPoints = _stockDataCache[stock.symbol] ?? [];
      if (dataPoints.isEmpty) continue;

      final groupedPoints = _groupData(dataPoints);
      final spots = groupedPoints.map((p) {
        final x = p.date.millisecondsSinceEpoch.toDouble();
        final y = _convertCurrency(p.price, stock.symbol);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        return FlSpot(x, y);
      }).toList();

      lineBarsData.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: stock.color,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: stock.color.withOpacity(0.05)),
      ));
    }

    // 여백 추가
    final yPadding = (maxY - minY) * 0.1;
    minY = max(0, minY - yPadding);
    maxY = maxY + yPadding;

    return LineChartData(
      lineBarsData: lineBarsData,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: (maxX - minX) / 5,
            getTitlesWidget: (value, meta) {
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return SideTitleWidget(
                meta: meta,
                child: Text(DateFormat('yy/MM').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 60,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                meta: meta,
                child: Text(_formatPrice(value), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY - minY) / 5),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white.withOpacity(0.8),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final stock = stocks[spot.barIndex];
              return LineTooltipItem(
                '${stock.symbol}: ${_formatPrice(spot.y)}',
                TextStyle(color: stock.color, fontWeight: FontWeight.bold, fontSize: 12),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  // 통화 변환 로직
  double _convertCurrency(double price, String symbol) {
    final original = _stockOriginalCurrency[symbol] ?? 'USD';
    final toUsd = _toUsdRates[original] ?? 1.0;
    final fromUsd = _fromUsdRates[_selectedCurrency] ?? 1.0;
    return price * toUsd * fromUsd;
  }

  String _formatPrice(double value) {
    final formatter = NumberFormat.compact(locale: 'ko_KR');
    String currencySymbol = '';
    if (_selectedCurrency == '달러') currencySymbol = "\$";
    if (_selectedCurrency == '원화') currencySymbol = "₩";
    if (_selectedCurrency == '유로') currencySymbol = "€";
    return "$currencySymbol${formatter.format(value)}";
  }

  // 데이터 그룹화 로직 (일/주/월/년)
  List<StockDataPoint> _groupData(List<StockDataPoint> data) {
    if (_selectedUnit == '일') return data;
    
    final Map<String, List<double>> groups = {};
    final Map<String, DateTime> groupDates = {};

    for (var p in data) {
      String key;
      if (_selectedUnit == '주') {
        final wk = p.date.subtract(Duration(days: p.date.weekday - 1));
        key = DateFormat('yyyy-MM-dd').format(wk);
      } else if (_selectedUnit == '월') {
        key = DateFormat('yyyy-MM').format(p.date);
      } else {
        key = DateFormat('yyyy').format(p.date);
      }
      
      if (!groups.containsKey(key)) {
        groups[key] = [];
        groupDates[key] = p.date;
      }
      groups[key]!.add(p.price);
    }

    return groups.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return StockDataPoint(groupDates[e.key]!, avg);
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Widget _buildLegend() {
    final activeStocks = _selectedSlotStocks.whereType<Stock>().toList();
    if (activeStocks.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: activeStocks.map((s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(s.symbol, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      )).toList(),
    );
  }

  Widget _buildCollapsibleLog() {
    return ExpansionTile(
      title: const Text('통신 로그', style: TextStyle(fontSize: 12, color: Colors.grey)),
      dense: true,
      children: [
        Container(
          height: 150,
          color: Colors.black.withOpacity(0.05),
          child: ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(_logs[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeBadge(Stock s) {
    String text = '';
    Color color = Colors.grey;
    final ex = s.exchange?.toUpperCase() ?? '';
    
    if (ex.contains('KSC') || ex.contains('KOSPI')) { text = '코스피'; color = Colors.red.shade400; }
    else if (ex.contains('KSD') || ex.contains('KOSDAQ')) { text = '코스닥'; color = Colors.blue.shade400; }
    else if (ex.contains('NAS')) { text = '나스닥'; color = Colors.orange.shade400; }
    else if (ex.contains('NYQ')) { text = '뉴욕'; color = Colors.indigo.shade400; }
    else if (ex.contains('LSE')) { text = '런던'; color = Colors.purple.shade400; }
    else if (ex.contains('TYO')) { text = '도쿄'; color = Colors.green.shade400; }
    else { text = ex; color = Colors.grey; }

    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
