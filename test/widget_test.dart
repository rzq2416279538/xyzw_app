import 'package:flutter_test/flutter_test.dart';
import 'package:xyzw_app/data/account.dart';

void main() {
  test('bytesToHex matches naiwa ByteArray.toHex style', () {
    expect(Account.bytesToHex([0x00, 0xff, 0x0a]), '00ff0a');
  });

  test('displayName strips .bin', () {
    final a = Account(id: '1', name: '角色.bin', binHex: 'aa');
    expect(a.displayName, '角色');
  });
}
