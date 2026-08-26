import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2board_sdk/flutter_v2board_sdk.dart';

void main() {
  late _V2BoardStubServer backend;

  setUp(() async {
    backend = await _V2BoardStubServer.start();
    V2BoardSDK.instance.dispose();
    await V2BoardSDK.instance.initialize(
      backend.baseUrl,
      panelType: 'v2board',
      useMemoryStorage: true,
      httpConfig: const HttpConfig(userAgent: 'Orange-V2Board-Test'),
    );
  });

  tearDown(() async {
    V2BoardSDK.instance.dispose();
    await backend.close();
  });

  test('uses raw auth_data for protected V2Board APIs', () async {
    final loggedIn = await V2BoardSDK.instance.loginWithCredentials(
      'orange@example.com',
      'password123',
    );

    expect(loggedIn, isTrue);
    expect(await V2BoardSDK.instance.getToken(), 'v2board-auth-data');

    final user = await V2BoardSDK.instance.user.getUserInfo();
    final subscription = await V2BoardSDK.instance.subscription
        .getSubscription();
    final passwordChanged = await V2BoardSDK.instance.user.changePassword(
      'old-password',
      'new-password',
    );
    final securityReset = await V2BoardSDK.instance.user.resetSecurity();

    expect(user.email, 'orange@example.com');
    expect(subscription.subscribeUrl, 'https://panel.example/sub/token');
    expect(passwordChanged, isTrue);
    expect(securityReset, isTrue);
    expect(
      backend.authorizationHeaders,
      everyElement(equals('v2board-auth-data')),
    );
    expect(
      backend.authorizationHeaders,
      isNot(contains(startsWith('Bearer '))),
    );
  });

  test('maps registration, plans, payments and order responses', () async {
    final registered = await V2BoardSDK.instance.auth.register(
      'new@example.com',
      'password123',
      emailCode: '123456',
      inviteCode: 'INVITE01',
    );

    expect(registered, isTrue);
    expect(backend.registrationBody, {
      'email': 'new@example.com',
      'password': 'password123',
      'email_code': '123456',
      'invite_code': 'INVITE01',
    });

    await V2BoardSDK.instance.loginWithCredentials(
      'orange@example.com',
      'password123',
    );

    final plans = await V2BoardSDK.instance.plan.getPlans();
    final methods = await V2BoardSDK.instance.payment.getPaymentMethods();
    final tradeNo = await V2BoardSDK.instance.order.createOrder(1, 'month');
    final orders = await V2BoardSDK.instance.order.getOrders();
    final coupon = await V2BoardSDK.instance.order.checkCoupon('SAVE10', 1);
    final checkout = await V2BoardSDK.instance.order.checkoutOrder(
      'ORDER-1',
      '7',
    );
    final canceled = await V2BoardSDK.instance.order.cancelOrder('ORDER-1');

    expect(plans, hasLength(1));
    expect(plans.single.monthPrice, 9.9);
    expect(tradeNo, 'ORDER-1');
    expect(backend.orderBody, {'plan_id': 1, 'period': 'month_price'});
    expect(orders.single.totalAmount, 9.9);
    expect(orders.single.orderPlan?.onetimePrice, 9.9);
    expect(coupon?.value, 100);
    expect(coupon?.limitPlanIds, ['1', '2']);
    expect(methods.single.paymentMethod, 'EPay');
    expect(methods.single.handlingFeeFixed, 50);
    expect(methods.single.handlingFeePercent, 2.5);
    expect(
      checkout.maybeWhen(
        redirect: (url, method, headers) => url,
        orElse: () => null,
      ),
      'https://pay.example/ORDER-1',
    );
    expect(canceled, isTrue);
  });

  test('uses wyx2685/v2board invite and commission routes', () async {
    await V2BoardSDK.instance.loginWithCredentials(
      'orange@example.com',
      'password123',
    );

    final code = await V2BoardSDK.instance.invite.generateInviteCode();
    final details = await V2BoardSDK.instance.invite.getCommissionDetails();
    final transferred = await V2BoardSDK.instance.invite
        .transferCommissionToBalance(12.5);

    expect(code, 'INVITE01');
    expect(details.single.tradeNo, 'ORDER-1');
    expect(transferred, isTrue);
    expect(backend.transferBody, {'transfer_amount': 1250});
    expect(backend.requestedPaths, contains('/api/v1/user/invite/save'));
    expect(backend.requestedPaths, contains('/api/v1/user/invite/details'));
    expect(backend.requestedPaths, isNot(contains('/api/v1/user/comm/fetch')));
  });
}

class _V2BoardStubServer {
  _V2BoardStubServer._(this._server) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final List<String?> authorizationHeaders = [];
  final List<String> requestedPaths = [];
  Map<String, dynamic>? registrationBody;
  Map<String, dynamic>? orderBody;
  Map<String, dynamic>? transferBody;
  bool inviteGenerated = false;

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_V2BoardStubServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _V2BoardStubServer._(server);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    requestedPaths.add(path);

    final isPublic = path.startsWith('/api/v1/passport/');
    if (!isPublic) {
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
    }

    final body = await _readJsonBody(request);
    Object response;

    switch ('${request.method} $path') {
      case 'POST /api/v1/passport/auth/login':
        response = {
          'data': {
            'token': 'subscription-token',
            'auth_data': 'v2board-auth-data',
            'is_admin': false,
          },
        };
      case 'POST /api/v1/passport/auth/register':
        registrationBody = body;
        response = {
          'data': {
            'token': 'new-subscription-token',
            'auth_data': 'new-v2board-auth-data',
          },
        };
      case 'GET /api/v1/user/info':
        response = {
          'data': {
            'email': 'orange@example.com',
            'uuid': 'user-uuid',
            'transfer_enable': 107374182400,
            'balance': 1000,
            'commission_balance': 500,
            'banned': 0,
            'remind_expire': 1,
            'remind_traffic': 1,
          },
        };
      case 'GET /api/v1/user/getSubscribe':
        response = {
          'data': {
            'plan_id': 1,
            'token': 'subscription-token',
            'expired_at': 1893456000,
            'u': 1024,
            'd': 2048,
            'transfer_enable': 107374182400,
            'device_limit': 3,
            'email': 'orange@example.com',
            'uuid': 'user-uuid',
            'subscribe_url': 'https://panel.example/sub/token',
            'plan': {
              'id': 1,
              'name': 'Standard',
              'transfer_enable': 100,
              'speed_limit': 200,
            },
          },
        };
      case 'POST /api/v1/user/changePassword':
        response = {'data': true};
      case 'GET /api/v1/user/resetSecurity':
        response = {'data': 'https://panel.example/sub/new-token'};
      case 'GET /api/v1/user/plan/fetch':
        response = {
          'data': [
            {
              'id': 1,
              'group_id': 1,
              'transfer_enable': 100,
              'name': 'Standard',
              'show': 1,
              'renew': 1,
              'month_price': 990,
            },
          ],
        };
      case 'GET /api/v1/user/order/getPaymentMethod':
        response = {
          'data': [
            {
              'id': 7,
              'name': 'Online payment',
              'payment': 'EPay',
              'handling_fee_fixed': 50,
              'handling_fee_percent': 2.5,
            },
          ],
        };
      case 'POST /api/v1/user/order/save':
        orderBody = body;
        response = {'data': 'ORDER-1'};
      case 'GET /api/v1/user/order/fetch':
        response = {
          'data': [
            {
              'plan_id': 1,
              'trade_no': 'ORDER-1',
              'total_amount': 990,
              'period': 'month_price',
              'status': 0,
              'created_at': 1700000000,
              'plan': {
                'id': 1,
                'name': 'Standard',
                'onetime_price': 990,
              },
            },
          ],
        };
      case 'POST /api/v1/user/coupon/check':
        response = {
          'data': {
            'id': 1,
            'name': 'Save 1 yuan',
            'code': 'SAVE10',
            'type': 1,
            'value': 100,
            'limit_plan_ids': [1, 2],
            'limit_period': ['month_price'],
            'show': 1,
          },
        };
      case 'POST /api/v1/user/order/checkout':
        response = {'type': 1, 'data': 'https://pay.example/ORDER-1'};
      case 'POST /api/v1/user/order/cancel':
        response = {'data': true};
      case 'GET /api/v1/user/invite/save':
        inviteGenerated = true;
        response = {'data': true};
      case 'GET /api/v1/user/invite/fetch':
        response = {
          'data': {
            'codes': [
              {
                'user_id': 1,
                'code': 'EXISTING',
                'pv': 0,
                'status': 0,
                'created_at': 1700000000,
                'updated_at': 1700000000,
              },
              if (inviteGenerated)
                {
                  'user_id': 1,
                  'code': 'INVITE01',
                  'pv': 0,
                  'status': 0,
                  'created_at': 1700000001,
                  'updated_at': 1700000001,
                },
            ],
            'stat': [1, 200, 50, 10, 100],
          },
        };
      case 'GET /api/v1/user/invite/details':
        response = {
          'data': [
            {
              'id': 1,
              'order_amount': 990,
              'trade_no': 'ORDER-1',
              'get_amount': 99,
              'created_at': 1700000000,
            },
          ],
          'total': 1,
        };
      case 'POST /api/v1/user/transfer':
        transferBody = body;
        response = {'data': true};
      default:
        request.response.statusCode = HttpStatus.notFound;
        response = {'message': 'Unhandled ${request.method} $path'};
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    if (request.method == 'GET') return <String, dynamic>{};
    final raw = await utf8.decoder.bind(request).join();
    if (raw.isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
