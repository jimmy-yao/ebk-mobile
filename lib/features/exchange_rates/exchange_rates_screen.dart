import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/util/money.dart';
import '../../data/repositories/exchange_rate_repository.dart';
import '../accounts/accounts_screen.dart';

/// 汇率页：展示服务端最新汇率（基准货币 / 数据来源 / 更新时间）+ 换算小工具。
///
/// **只读**：网页端能增删"用户自定义汇率"，但那套接口只在服务端把数据源配成
/// `user_custom` 时才会生效（本实例是 European Central Bank ——
/// `exchangerates/common_http_exchange_rates_data_provider.go` 只发外部源的
/// 请求，不合并自定义项）。MVP 不给"改了也没用"的入口，契约见方案文档 §1。
class ExchangeRatesScreen extends ConsumerWidget {
  const ExchangeRatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(exchangeRatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('汇率'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(exchangeRatesProvider),
          ),
        ],
      ),
      body: ratesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(exchangeRatesProvider),
        ),
        data: (rates) {
          if (rates.entries.isEmpty) {
            return const Center(child: Text('服务端没有可用的汇率数据'));
          }
          return _RatesView(rates: rates);
        },
      ),
    );
  }
}

class _RatesView extends StatelessWidget {
  const _RatesView({required this.rates});

  final ExchangeRates rates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '基准货币 ${rates.baseCurrency}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('数据来源 ${_sourceLabel(rates.dataSource)}'),
                const SizedBox(height: 4),
                Text(
                  '更新时间 ${_updateText(rates.updateTime)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '跨币种记账与统计都按下面的汇率换算到你的默认币种，'
                  '换不了的条目会整条跳过（与网页端一致）。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Converter(rates: rates),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            '汇率列表',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        for (final e in rates.entries)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 44,
              child: Text(
                e.currency,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.right,
              ),
            ),
            title: Text(
              '1 ${rates.baseCurrency} = ${_rateText(e.rate)} ${e.currency}',
            ),
          ),
      ],
    );
  }
}

class _Converter extends StatefulWidget {
  const _Converter({required this.rates});

  final ExchangeRates rates;

  @override
  State<_Converter> createState() => _ConverterState();
}

class _ConverterState extends State<_Converter> {
  late final TextEditingController _amountCtrl;
  late String _from;
  late String _to;

  @override
  void initState() {
    super.initState();
    final currencies = widget.rates.entries.map((e) => e.currency).toList();
    final base = widget.rates.baseCurrency.toUpperCase();
    _from = currencies.contains(base) ? base : currencies.first;
    _to = currencies.firstWhere((c) => c != _from, orElse: () => _from);
    _amountCtrl = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = widget.rates.entries.map((e) => e.currency).toList();

    // 金额按「最小单位整数」换算，全程不碰 double（多币种精度要求）
    final minor = parseDecimalToMinor(_amountCtrl.text);
    final converted = widget.rates.convert(minor, _from, _to);

    final result = converted == null
        ? '$_from 暂无可用汇率'
        : '${formatAmount(minor, _from)} $_from = '
            '${formatAmount(converted, _to)} $_to';

    DropdownButton<String> dropdown(String value, void Function(String) on) =>
        DropdownButton<String>(
          value: value,
          isDense: true,
          items: [
            for (final c in currencies)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => on(v));
          },
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('换算', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '金额',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                dropdown(_from, (v) => _from = v),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.arrow_forward, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                dropdown(_to, (v) => _to = v),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceLabel(String dataSource) {
  if (dataSource == 'user_custom') return '用户自定义';
  if (dataSource.isEmpty) return '未知';
  return dataSource;
}

String _updateText(int unixSeconds) {
  if (unixSeconds <= 0) return '未知';
  return DateFormat('yyyy-MM-dd HH:mm').format(
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000),
  );
}

/// 汇率展示：`7.5118` → `7.5118`，`1.0000` → `1`，`24.4560` → `24.456`
String _rateText(double rate) {
  if (rate <= 0) return '$rate';
  var text = rate.toStringAsFixed(4);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
