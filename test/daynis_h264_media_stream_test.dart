import 'package:flutter_test/flutter_test.dart';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';

void main() {
  test('adds one to input values', () {
    final calculator = Calculator();
    expect(calculator.addOne(2), 3);
    expect(calculator.addOne(-7), -6);
    expect(calculator.addOne(0), 1);
  });
}