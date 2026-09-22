# Live session ownership transfer: proposed server contract

This document accompanies a **client-side draft**, not an assertion that the
production EltenLink server implements this endpoint. The server implementation
is not in this repository. The route, fields and failure codes below need
maintainer agreement and server implementation before the feature can ship.

## Purpose and scope

A hosted application should be able to hand an existing live session to one of
its current participants without creating a new room or copying its event stack.
An owner wishing to leave should be able to transfer and leave atomically, so a
second handover or departure cannot slip between these two operations.

The proposal adds an explicit operation. It does not change ordinary `leave`,
`close`, expiry, invitations or creation defaults. There is no automatic election
on disconnect, crash, endpoint disposal or lease expiry. Such a policy needs a
separate server design; clients must not independently elect competing owners.

## Proposed request

Advertise `limits["ownership_transfer"]: true` only when the complete contract
is available. Absent, false or non-boolean values mean unsupported. The client
refuses the operation without sending it when the capability is unavailable.

Authenticated `POST /api/v1/apps/live-sessions/{session_id}/ownership`:

```json
{
  "participant_id": "current-owner-membership",
  "new_owner_id": "successor-membership",
  "leave": false,
  "request_id": "per-call-uuid"
}
```

`leave` is a strict boolean. The client generates a fresh UUID for each explicit
call and makes one attempt through the existing bounded, cancellable request
queue. It does not retry this operation automatically. A request which was not
confirmed must never trigger a fallback `close` or `leave`.

The server must, under the same session transaction/lock:

1. Authenticate the caller and application and verify its exact live membership.
   Do not accept a caller-supplied participant ID as proof of identity.
2. Deduplicate by session, authenticated initiating membership and request ID.
   Identical duplicates return the original result without another mutation;
   reuse with different arguments is a conflict. An authenticated duplicate of
   a successful `leave: true` must be retrievable after that membership left.
   Retain the receipt for the remaining session lifetime.
3. Verify the caller is still the owner and the successor is a different, active
   membership of the same session. Expired or departed members and invitations
   are not eligible. Concurrent departure/expiry and two competing transfers
   must be serialized; at most one transfer can succeed under that owner.
4. Change the owner and increment the session revision. If `leave` is true,
   remove the former owner in the same transaction, without closing the session.
5. Preserve session ID, other membership IDs, stack contents and cursors, pools,
   private draw ownership, random state, capacity, metadata, visibility and join
   code. Do not reset or extend other participants' leases as a side effect.
6. Derive all owner-only permissions and discovery ownership from the new owner.
   Ensure a formerly created private session does not remain owner-accessible
   to a departed creator solely because of an immutable creator field. Existing
   invitations retain their original inviter identity and existing rules; do not
   reissue notifications or discard invitations as a side effect of handover.
7. Publish an ordered `owner_changed` event, then `participant_left` if requested.
   Commit these events, the snapshot and the operation receipt together.

Authorization must remain enforced on every owner-only server operation after
handover, including delayed requests from the former owner. Application clients'
local `owner?` checks are convenience, not the security boundary.

## Confirmation and events

The normal `success: true` response contains a full session snapshot in `data`,
as observed immediately after this transaction. It includes `id`, `revision`,
the initiating `participant_id`, the new `owner_id`, `participants`, limits and
the other normal session fields. Additionally it contains `request_id`,
`previous_owner_id` and `left`. With `leave: true`, `participants` excludes the
initiating membership; `participant_id` identifies the receipt's caller, not a
renewed membership. The successor must be in that snapshot.

The client checks these receipt fields before applying the snapshot. The usual
revision guard prevents a late confirmation from overwriting a newer owner.
Only a valid confirmation of `leave: true` closes the local membership with
reason `:left`; it does not queue a separate departure. A newer authoritative
event may already have changed the owner again when the call returns.

The ordered server event is:

```json
{
  "type": "owner_changed",
  "seq": 42,
  "owner_id": "successor-membership",
  "owner": {
    "id": "successor-membership",
    "user": "bob",
    "metadata": {},
    "joined_at": 1234567890
  }
}
```

It travels in ordinary realtime/recovery envelopes, with the authoritative
revision-checked session snapshot. Its `owner` row is necessary when replaying a
change to a member who has since left. The client queues `on_owner_changed` in
the existing callback dispatcher, subject to ordinary event cursor deduplication.
It does not turn application messages with a similar payload into system events.

As with participant and discovery callbacks, this is an event notification, not
a guarantee that the callback's owner is still current when it runs. Read
`session.owner` / `owner?` when reconciling current duties. The callback receives
an immutable copy; applying a historical event must not roll back the snapshot.
The HTTP response and initial snapshots do not synthesize this callback. When
history has expired, `on_gap` and the current snapshot are the recovery path.

## Errors, uncertainty and compatibility

Use the normal structured error response. Existing errors for a missing/closed
session, missing membership, non-owner or unsupported feature retain their
meaning. Proposed additional validation can use
`apps.live_sessions.participant_not_found` for a departed successor; malformed
arguments and conflicting request IDs must not change any state.

A timeout, cancellation, disconnected caller or lost reply after commit is an
**unknown outcome**, not a rollback. The client stays in its current local state
unless it has received authoritative updates, and sends no fallback departure.
Normal recovery must report the committed snapshot or the removed membership;
the server must not resurrect that membership or undo the transfer. An explicit
subsequent attempt is a new operation and requires a fresh ownership check.

Older clients already read `owner_id` from snapshots and ignore unknown event
types. They do not gain the new application callback. Applications which assume
an immutable creator/owner must be updated separately: historical game actions
must remain valid under the authority that existed when they were accepted.
Bot scheduling, saved tables and a separate Communications session need their
own handover logic. This client PR does not modify Game Room or either of those
application-specific policies.

## Verification and remaining server work

`ruby tests/live_session_ownership_test.rb` exercises the real client request
queue and event handling against stubbed HTTP replies, without a live account.
It covers capability checks, same-session membership, loss of authority while
queued, transfer with/without departure, rejection, cancellation, timeout,
invalid confirmations, replay/gaps, later transfers and legacy leave/close.
This is not a test of server transactions, authentication or production delivery.

Before enabling the capability, server integration tests must additionally
cover concurrent transfer/leave/expiry, duplicate request receipts (including
after departure), owner-only permissions, public/private discovery, stack/pool
preservation, delivery to all remaining participants, and recovery after a
committed operation whose response was lost. Test both older clients and the new
client. Do not deploy the capability based solely on the client tests.
