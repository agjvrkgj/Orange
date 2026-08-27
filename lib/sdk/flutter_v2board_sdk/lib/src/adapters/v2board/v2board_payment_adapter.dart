import '../../api/interfaces/payment_api.dart';
import '../../api/models/payment_model.dart';
import '../../panels/v2board/apis/v2board_payment_api.dart';
import '../../panels/xboard/models/xboard_payment_models.dart';

class V2BoardPaymentAdapter implements PaymentApi {
  final V2BoardPaymentApi _api;

  V2BoardPaymentAdapter(this._api);

  @override
  Future<List<PaymentMethodModel>> getPaymentMethods() async {
    final response = await _api.getPaymentMethods();
    if (response.data == null) return [];
    return response.data!.map(_mapPaymentMethod).toList();
  }

  PaymentMethodModel _mapPaymentMethod(PaymentMethodInfo method) {
    return PaymentMethodModel(
      id: method.id.toString(),
      name: method.name,
      paymentMethod: method.payment ?? method.name,
      handlingFeeFixed: method.feeFixed,
      handlingFeePercent: method.feePercent,
      icon: method.icon,
      isAvailable: method.isAvailable,
      config: method.config,
      description: method.description,
      minAmount: method.minAmount,
      maxAmount: method.maxAmount,
    );
  }
}
