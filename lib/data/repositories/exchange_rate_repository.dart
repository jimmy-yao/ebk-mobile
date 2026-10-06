import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// 汇率（跨币种转账换算用）。
///
/// `GET /api/v1/exchange_rates/latest.json` →
/// ```json
/// { "dataSource": "European Central Bank", "baseCurrency": "EUR",
///   "exchangeRates": [ {"currency":"CNY","rate":"7.51"}, ... ] }
/// ```
/// rate 的语义是 **1 单位基准货币 = rate 个该货币**（ECB 报价，基准 EUR）。
/// 换算式与网页端 `lib/numeral.ts: getExchangedAmountByRate` 完全一致：
/// `目标金额 = 源金额 × rate目标 / rate源`（基准在比值里约掉，不必知道 base）。
class ExchangeRate {
  const ExchangeRate({required this.currency, required this.rate});

  final String currency;
  final double rate;
}

class ExchangeRates {
  const ExchangeRates({
    required this.baseCurrency,
    required this.rates,
    this.dataSource = '',
    this.referenceUrl = '',
    this.updateTime = 0,
  });

  final String baseCurrency;
  final Map<String, double> rates;

  /// 数据来源（实测 `European Central Bank`；服务端配成自定义源时是 `user_custom`）
  final String dataSource;
  final String referenceUrl;

  /// 服务端拿到这份汇率的时间（Unix 秒）
  final int updateTime;

  /// 按币种码升序的条目（汇率页展示用）。基准币种自己也在里面（rate=1）
  List<ExchangeRate> get entries {
    final list = [
      for (final e in rates.entries)
        ExchangeRate(currency: e.key, rate: e.value),
    ];
    return list..sort((a, b) => a.currency.compareTo(b.currency));
  }

  /// 从 [from] 币种换到 [to] 币种；拿不到汇率返回 null
  int? convert(int minorAmount, String from, String to) {
    if (from.toUpperCase() == to.toUpperCase()) return minorAmount;
    final fromRate = rates[from.toUpperCase()];
    final toRate = rates[to.toUpperCase()];
    if (fromRate == null || toRate == null || fromRate <= 0 || toRate <= 0) {
      return null;
    }
    final converted = minorAmount * toRate / fromRate;
    // 最小单位不能是小数，四舍五入
    final rounded = converted.round();
    return rounded;
  }
}

final exchangeRatesProvider = FutureProvider.autoDispose<ExchangeRates>((ref) async {
  final api = ref.watch(apiClientProvider);
  final result = await api.get('/api/v1/exchange_rates/latest.json');
  final map = result as Map<String, dynamic>;
  final rates = <String, double>{};
  for (final item in (map['exchangeRates'] as List<dynamic>? ?? const [])) {
    if (item is! Map<String, dynamic>) continue;
    final currency = item['currency']?.toString().toUpperCase();
    final rate = double.tryParse(item['rate']?.toString() ?? '');
    if (currency != null && rate != null) rates[currency] = rate;
  }
  return ExchangeRates(
    baseCurrency: map['baseCurrency']?.toString() ?? '',
    rates: rates,
    dataSource: map['dataSource']?.toString() ?? '',
    referenceUrl: map['referenceUrl']?.toString() ?? '',
    updateTime: int.tryParse(map['updateTime']?.toString() ?? '') ?? 0,
  );
});
