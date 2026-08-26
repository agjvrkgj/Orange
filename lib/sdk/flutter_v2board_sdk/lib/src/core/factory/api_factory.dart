import '../http/http_service.dart';
import '../../api/interfaces/user_api.dart';
import '../../api/interfaces/plan_api.dart';
import '../../api/interfaces/order_api.dart';
import '../../api/interfaces/subscription_api.dart';
import '../../api/interfaces/invite_api.dart';
import '../../api/interfaces/notice_api.dart';
import '../../api/interfaces/ticket_api.dart';
import '../../api/interfaces/config_api.dart';
import '../../api/interfaces/payment_api.dart';
import '../../api/interfaces/auth_api.dart';

import '../../panels/v2board/apis/v2board_login_api.dart';
import '../../panels/v2board/apis/v2board_register_api.dart';
import '../../panels/v2board/apis/v2board_user_info_api.dart';
import '../../panels/v2board/apis/v2board_send_email_code_api.dart';
import '../../panels/v2board/apis/v2board_reset_password_api.dart';
import '../../panels/v2board/apis/v2board_plan_api.dart';
import '../../panels/v2board/apis/v2board_order_api.dart';
import '../../panels/v2board/apis/v2board_payment_api.dart';
import '../../panels/v2board/apis/v2board_subscription_api.dart';
import '../../panels/v2board/apis/v2board_invite_api.dart';
import '../../panels/v2board/apis/v2board_ticket_api.dart';
import '../../panels/v2board/apis/v2board_notice_api.dart';
import '../../panels/v2board/apis/v2board_config_api.dart';
import '../../panels/v2board/apis/v2board_coupon_api.dart';

import '../../adapters/v2board/v2board_user_adapter.dart';
import '../../adapters/v2board/v2board_plan_adapter.dart';
import '../../adapters/v2board/v2board_order_adapter.dart';
import '../../adapters/v2board/v2board_subscription_adapter.dart';
import '../../adapters/v2board/v2board_invite_adapter.dart';
import '../../adapters/v2board/v2board_notice_adapter.dart';
import '../../adapters/v2board/v2board_ticket_adapter.dart';
import '../../adapters/v2board/v2board_config_adapter.dart';
import '../../adapters/v2board/v2board_payment_adapter.dart';
import '../../adapters/v2board/v2board_auth_adapter.dart';

import 'panel_type.dart';

class ApiFactory {
  final PanelType _panelType;
  final HttpService _httpService;

  ApiFactory(this._panelType, this._httpService);

  UserApi createUserApi() {
    _ensureV2Board();
    return V2BoardUserAdapter(V2BoardUserInfoApi(_httpService));
  }

  PlanApi createPlanApi() {
    _ensureV2Board();
    return V2BoardPlanAdapter(V2BoardPlanApi(_httpService));
  }

  OrderApi createOrderApi() {
    _ensureV2Board();
    return V2BoardOrderAdapter(
      V2BoardOrderApi(_httpService),
      V2BoardCouponApi(_httpService),
    );
  }

  SubscriptionApi createSubscriptionApi() {
    _ensureV2Board();
    return V2BoardSubscriptionAdapter(V2BoardSubscriptionApi(_httpService));
  }

  InviteApi createInviteApi() {
    _ensureV2Board();
    return V2BoardInviteAdapter(V2BoardInviteApi(_httpService));
  }

  NoticeApi createNoticeApi() {
    _ensureV2Board();
    return V2BoardNoticeAdapter(V2BoardNoticeApi(_httpService));
  }

  TicketApi createTicketApi() {
    _ensureV2Board();
    return V2BoardTicketAdapter(V2BoardTicketApi(_httpService));
  }

  ConfigApi createConfigApi() {
    _ensureV2Board();
    return V2BoardConfigAdapter(V2BoardConfigApi(_httpService));
  }

  PaymentApi createPaymentApi() {
    _ensureV2Board();
    return V2BoardPaymentAdapter(V2BoardPaymentApi(_httpService));
  }

  AuthApi createAuthApi() {
    _ensureV2Board();
    return V2BoardAuthAdapter(
      V2BoardLoginApi(_httpService),
      V2BoardRegisterApi(_httpService),
      V2BoardSendEmailCodeApi(_httpService),
      V2BoardResetPasswordApi(_httpService),
    );
  }

  void _ensureV2Board() {
    if (_panelType != PanelType.v2board) {
      throw StateError('Only the V2Board backend is supported.');
    }
  }
}
