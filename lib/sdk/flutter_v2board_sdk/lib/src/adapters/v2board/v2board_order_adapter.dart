import '../../api/interfaces/order_api.dart';
import '../../api/models/order_model.dart';
import '../../api/models/payment_model.dart';
import '../../api/models/coupon_model.dart';
import '../../panels/v2board/apis/v2board_order_api.dart';
import '../../panels/v2board/apis/v2board_coupon_api.dart';
import '../../panels/xboard/models/xboard_order_models.dart';
import '../../panels/xboard/models/xboard_coupon_models.dart'; // Reusing XBoard models if compatible, or V2Board models

class V2BoardOrderAdapter implements OrderApi {
  final V2BoardOrderApi _api;
  final V2BoardCouponApi _couponApi;

  V2BoardOrderAdapter(this._api, this._couponApi);

  @override
  Future<List<OrderModel>> getOrders({int page = 1, int pageSize = 10}) async {
    final response = await _api.fetchUserOrders();
    return response.data.map(_mapOrder).toList();
  }

  @override
  Future<String> createOrder(int planId, String period,
      {String? couponCode}) async {
    final response = await _api.createOrder(
      planId: planId,
      period: _v2BoardPeriod(period),
      couponCode: couponCode,
    );
    if (response.data == null) {
      throw Exception('Order creation failed: no data returned');
    }
    return response.data!;
  }

  @override
  Future<List<PaymentMethodModel>> getPaymentMethods(String tradeNo) async {
    // V2Board API returns all payment methods, tradeNo is not used in this specific API call
    final response = await _api.getPaymentMethods();
    if (response.data == null) return [];
    return response.data!.map(_mapPaymentMethod).toList();
  }

  @override
  Future<PaymentResultModel> checkoutOrder(
      String tradeNo, String method) async {
    final response = await _api.submitPayment(tradeNo: tradeNo, method: method);

    if (response.type == -1) {
      return const PaymentResultModel.success(message: 'Payment successful');
    }

    // wyx2685/v2board uses 0 for QR-code payloads and 1 for redirect URLs.
    // Both are URI strings that the Orange payment page can open externally.
    if ((response.type == 0 || response.type == 1) &&
        response.data is String &&
        (response.data as String).isNotEmpty) {
      return PaymentResultModel.redirect(url: response.data as String);
    }

    return PaymentResultModel.failed(
      message: 'Unsupported V2Board payment result type: ${response.type}',
    );
  }

  @override
  Future<bool> cancelOrder(String tradeNo) async {
    final response = await _api.cancelOrder(tradeNo);
    return response.success && response.data == true;
  }

  Future<PaymentMethodModel?> getOrderPaymentMethod(String tradeNo) async {
    // V2BoardOrderApi doesn't have getOrderPaymentMethod.
    // It has getPaymentMethods() which returns all methods.
    return null;
  }

  @override
  Future<OrderModel> getOrder(String tradeNo) async {
    final order = await _api.getOrderDetails(tradeNo);
    return _mapOrder(order);
  }

  OrderModel _mapOrder(Order order) {
    return OrderModel(
      planId: order.planId,
      tradeNo: order.tradeNo,
      totalAmount:
          order.totalAmount == null ? null : order.totalAmount! / 100,
      period: order.period,
      status: order.status,
      createdAt: order.createdAt,
      orderPlan:
          order.orderPlan != null ? _mapOrderPlan(order.orderPlan!) : null,
    );
  }

  OrderPlanModel _mapOrderPlan(OrderPlan plan) {
    return OrderPlanModel(
      id: plan.id,
      name: plan.name,
      onetimePrice:
          plan.onetimePrice == null ? null : plan.onetimePrice! / 100,
      content: plan.content,
    );
  }

  PaymentMethodModel _mapPaymentMethod(PaymentMethod method) {
    return PaymentMethodModel(
      id: method.id,
      name: method.name,
      paymentMethod: method.name, // Fallback to name
      icon: method.icon,
      isAvailable: method.isAvailable,
      config: method.config,
    );
  }

  @override
  Future<CouponModel?> checkCoupon(String code, int planId) async {
    try {
      final response = await _couponApi.checkCoupon(code, planId);
      if (response.data == null) return null;
      return _mapCoupon(response.data!);
    } catch (e) {
      return null;
    }
  }

  CouponModel _mapCoupon(CouponData coupon) {
    return CouponModel(
      id: coupon.id,
      name: coupon.name,
      code: coupon.code,
      type: coupon.type,
      value: coupon.value,
      limitUse: coupon.limitUse,
      limitUseWithUser: coupon.limitUseWithUser,
      limitPlanIds: coupon.limitPlanIds,
      limitPeriod: coupon.limitPeriod,
      startedAt: coupon.startedAt,
      endedAt: coupon.endedAt,
      show: coupon.show,
      createdAt: coupon.createdAt,
      updatedAt: coupon.updatedAt,
    );
  }

  String _v2BoardPeriod(String period) {
    const periods = {
      'onetime': 'onetime_price',
      'month': 'month_price',
      'quarter': 'quarter_price',
      'half_year': 'half_year_price',
      'year': 'year_price',
      'two_year': 'two_year_price',
      'three_year': 'three_year_price',
      'reset': 'reset_price',
    };
    return periods[period] ?? period;
  }
}
