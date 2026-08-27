# Flutter V2Board SDK

Orange's in-repository V2Board client. It is aligned with
[`wyx2685/v2board`](https://github.com/wyx2685/v2board) master commit
`25ab8e081c3dbcdae365bbed558aff63695d4675`.

Supported application flows:

- email/password authentication using raw V2Board `auth_data`
- user and subscription information
- plans, coupons, orders, payment methods, and checkout
- notices, tickets, invite codes, commission history, and balance transfer

## Authentication contract

V2Board returns both a subscription `token` and an authentication
`auth_data` value from `/api/v1/passport/auth/login`. Protected API requests
must send `auth_data` unchanged in the `Authorization` header. A `Bearer`
prefix is deliberately not added.

## Generate models

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

The package is vendored in Orange because the previous external XBoard SDK
submodule is not writable by the Orange repository owner, while V2Board
compatibility fixes need to be versioned atomically with the application.
