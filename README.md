# Communal Collector

The app for cooperative **collectors** — the people a cooperative sends out to take
contributions in cash from members who cannot use the member app themselves.

It is a separate app from `mobile/` (the member app) on purpose. A collector holds no
dashboard permission and reaches only ten routes across two services; bolting a
cash-handling mode onto the member app would have put a float, a cash limit and a
commission ledger in front of every member who never asked for one.

## What a collector can do

| Tab | What it is |
|---|---|
| **Round** | The members this cooperative allows this collector to collect from, searchable by name, ledger number or phone. Tapping one opens the receipt. |
| **Receipts** | Everything written, with what is still on the phone kept visually apart from what the cooperative has. A refused receipt can be re-sent or discarded; a merely unsent one cannot be discarded — the cash was taken, so the record is owed. |
| **Remit** | Declare cash handed back into one of the cooperative's own accounts. It leaves the float only when an administrator confirms it. |
| **Earnings** | Commission: still to be paid, on a payout awaiting a second administrator, and paid. |

Above all four sits the standing: **cash in your hands** — the float plus what is
declared and not yet countersigned — against the limit the cooperative set.

## The terms are the cooperative's, not the app's

Everything about how a collector operates comes down with the grant and is only ever
displayed here:

- **Settlement mode** — `on_collection` moves the member's obligations the moment the
  receipt lands; `on_remittance` waits for an administrator to countersign the cash.
- **Commission** — a percentage in basis points, or a flat amount per collection.
- **Cash limit** — the ceiling on what the collector may be holding at once.

A person can collect for more than one cooperative on different terms, so the app is
always acting under exactly one grant and says which in the app bar.

## Offline

A collector's round is a walk through a neighbourhood, and the parts with no coverage
are exactly the parts where members cannot use the app themselves. So:

- The roster, a member's obligations and the standing are cached read-through, and
  every cached read is labelled on screen as coming off the device.
- A receipt is written to a local outbox **first and always** — the collector is
  standing in front of a member, and a spinner that fails is not an answer.
- The queue is sent oldest-first, one at a time, on connectivity change, on app
  resume, on pull-to-refresh and right after recording. Order matters: the server
  checks each collection against what the collector is already holding.
- The receipt number is `<install-salt>-<counter>`. The counter is what the collector
  reads out to the member; the salt is what stops a reinstall restarting the counter
  onto numbers the server has already filed, which would make a real collection
  resolve as an idempotent resend and vanish.

## Running it

Values arrive through `--dart-define`, never a bundled asset:

```bash
cp tool/dart_defines.example.json tool/dart_defines.json   # then set BASE_URL
flutter run --dart-define-from-file=tool/dart_defines.json
```

`BASE_URL` is only read when `APP_ENV` is `development`; staging and production
origins are compiled in. It must be reachable **from the handset**, so it is the dev
machine's LAN address and port `8989` (the local gateway) rather than `127.0.0.1` —
that address moves around, which is exactly why it is a define.

## Backends

Ten routes, all of which reject anything but a `collector`-guard token:

- **authsvc** — `collector/login-request`, `login-resend`, `login-verify`,
  `refresh-token`. Sign-in is a three-step OTP challenge, not a password: a collector
  who is already a member has the same 6-digit PIN every member has, and one
  registered only as a collector sets theirs at verify time. The cooperative is chosen
  at verify time because the token carries `coop_id` and `collector_id`.
- **obligations-svc** — `collector/members`, `members/{ledger}/obligations`,
  `collections`, `standing`, `earnings`.
- **cooperative-svc** — `collector/accounts`, `remittance-accounts`, `remittances`.

The account a collection is credited to is **not** the client's choice — the server
forces the collector's own float repository — so no request from this app carries a
`cash_repository_id`. There is a test that keeps it that way.

All amounts on the wire are **kobo**. The screens are the only place a major-unit
figure exists.

## Checks

```bash
flutter analyze
flutter test
```
