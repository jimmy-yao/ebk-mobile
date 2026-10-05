import 'package:ebk_mobile/core/util/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAmount', () {
    test('两位小数货币按最小单位换算', () {
      expect(formatAmount(1234, 'CNY'), '12.34');
      expect(formatAmount(0, 'CNY'), '0.00');
      expect(formatAmount(5, 'CNY'), '0.05');
      expect(formatAmount(-500, 'USD'), '-5.00');
      expect(formatAmount(10000, 'EUR'), '100.00');
    });

    test('0 位小数货币不显示小数', () {
      expect(formatAmount(10000, 'JPY'), '100');
      expect(formatAmount(1234, 'JPY'), '12');
      expect(formatAmount(-2500, 'KRW'), '-25');
    });

    test('大小写不敏感', () {
      expect(formatAmount(10000, 'jpy'), '100');
    });
  });

  group('currencyFraction', () {
    test('常见货币小数位', () {
      expect(currencyFraction('CNY'), 2);
      expect(currencyFraction('JPY'), 0);
      expect(currencyFraction('KRW'), 0);
      expect(currencyFraction('BHD'), 3);
      // 未收录货币按 2 位兜底
      expect(currencyFraction('XXX'), 2);
    });
  });

  group('parseDecimalToMinor', () {
    test('十进制字符串 → 最小单位', () {
      expect(parseDecimalToMinor('12.34'), 1234);
      expect(parseDecimalToMinor('0.05'), 5);
      expect(parseDecimalToMinor('-3.5'), -350);
      expect(parseDecimalToMinor('100'), 10000);
      expect(parseDecimalToMinor(''), 0);
    });
  });

  group('minorToInput', () {
    test('最小单位 → 输入框文本（固定两位）', () {
      expect(minorToInput(1234), '12.34');
      expect(minorToInput(5), '0.05');
      expect(minorToInput(0), '0.00');
      expect(minorToInput(-1234), '-12.34');
      expect(minorToInput(10000), '100.00');
    });

    test('与 parseDecimalToMinor 严格往返（编辑回填不丢精度）', () {
      for (final minor in [0, 1, 5, 99, 100, 1234, 999999, -1, -1234]) {
        expect(parseDecimalToMinor(minorToInput(minor)), minor,
            reason: 'minor=$minor');
      }
    });
  });
}
