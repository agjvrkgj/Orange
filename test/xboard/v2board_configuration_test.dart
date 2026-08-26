import 'package:fl_clash/xboard/config/models/parsed_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy remote config cannot switch Orange back to XBoard', () {
    final configuration = ParsedConfiguration.fromJson({
      'panelType': 'xboard',
      'panels': {
        'Orange': [
          {'url': 'https://panel.example'},
        ],
      },
    }, 'Orange');

    expect(configuration.panelType, 'v2board');
    expect(configuration.firstPanelUrl, 'https://panel.example');
  });

  test('panelType is optional for new V2Board remote config', () {
    final configuration = ParsedConfiguration.fromJson(
      const <String, dynamic>{},
      'Orange',
    );

    expect(configuration.panelType, 'v2board');
  });
}
