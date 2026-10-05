/// 金额工具。
///
/// 服务端把金额存成 int64 **最小单位（分）**，网页端显示时 `amount / 100`
/// （见 src/components/desktop/CustomChart.vue），货币小数位见
/// src/consts/currency.ts 的 `fraction` 字段（JPY/KRW 等为 0）。
///
/// 账户接口的 `balance` 字段是**最小单位整数字符串**（服务端
/// `Balance: utils.Int64ToString(a.Balance)`，实测支出 1234 分后返回 `"-1234"`），
/// 展示时仍要用 [formatAmount] 除 100；[parseDecimalToMinor] 用于把输入框
/// 的十进制串转回最小单位。
library;

/// 常见 0 位小数货币（未收录的一律按 2 位处理）
const _zeroFractionCurrencies = <String>{
  'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'VUV', 'XAF', 'XOF', 'XPF', 'KMF',
  'GYD', 'RWF', 'UGX',
};

/// 该货币应该显示几位小数
int currencyFraction(String currency) {
  final code = currency.toUpperCase();
  if (_zeroFractionCurrencies.contains(code)) return 0;
  if (code == 'BHD' || code == 'KWD' || code == 'OMR' || code == 'TND') {
    return 3;
  }
  return 2;
}

/// 把最小单位金额格式化成展示字符串。
///
/// [minor] 1234 + CNY → "12.34"；1234 + JPY → "12"（按 JPY 0 位小数）
/// 注意 3 位小数货币（BHD 等）服务端仍按 100 存，这里只按 100 换算，
/// 尾数会在实测到这类账户后再修正。
String formatAmount(int minor, String currency) {
  final negative = minor < 0;
  final abs = minor.abs();
  final fraction = currencyFraction(currency);

  final major = abs ~/ 100;
  final cents = abs % 100;

  final buffer = StringBuffer();
  if (negative) buffer.write('-');
  buffer.write(major);

  if (fraction > 0) {
    buffer.write('.');
    buffer.write(cents.toString().padLeft(2, '0'));
    // fraction==3 时服务端只提供 2 位，保持两位展示（见上方说明）
    if (fraction == 3) buffer.write('0');
  }

  return buffer.toString();
}

/// 解析十进制字符串金额（如输入框 "12.34"）→ 最小单位
int parseDecimalToMinor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  final negative = trimmed.startsWith('-');
  final digits = negative ? trimmed.substring(1) : trimmed;
  final parts = digits.split('.');
  final major = int.tryParse(parts[0]) ?? 0;
  final fracRaw = parts.length > 1 ? parts[1] : '';
  final frac = int.tryParse(fracRaw.padRight(2, '0').substring(0, 2)) ?? 0;
  final minor = major * 100 + frac;
  return negative ? -minor : minor;
}

/// 最小单位 → 输入框文本，固定两位小数（`1234 → "12.34"`、`5 → "0.05"`）。
///
/// 和 [formatAmount] 不同：**不看货币小数位**，因为记账输入必须能原样回读
/// （`parseDecimalToMinor(minorToInput(x)) == x`），JPY 用户输入 "100.00"
/// 也照收，提交时就是 10000 分。
String minorToInput(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final text = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}
