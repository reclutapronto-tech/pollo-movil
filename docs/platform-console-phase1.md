# Pollo Móvil platform console — Phase 1

This change is local-only. It does not apply the migration to Supabase Staging,
deploy the Edge Function, change Vercel, or create customer records remotely.

## Invitation and audit behavior

- Creating a customer, the first corporate-admin invitation, and its initial
  audit event is one PostgreSQL transaction. An authorized license is not
  created automatically.
- Auth email delivery is an external side effect and cannot share the database
  transaction. The invitation row therefore records `pending_delivery`, `sent`,
  or `delivery_failed`; retries use the same invitation identity and never
  create a second Auth user intentionally. A provider may have accepted an
  email immediately before a network failure, so a retry can result in a second
  email. The invitation remains single-use and identity-bound.
- New Auth identities receive no company profile or role until the user follows
  the email link, verifies the same email, sets their own password, and claims
  the invitation. Existing Auth identities are not duplicated or reassigned;
  an existing profile in another company is refused. An unassigned existing
  identity receives a password-recovery link to prove mailbox control and may
  choose a new password before claiming.
- Revoking an invitation invalidates its database claim. A previously delivered
  Auth link may still establish an Auth session, but cannot restore company
  access after revocation.
- Password-reset and invitation credentials are not written to new audit rows.
  New platform-admin invitation rows store a SHA-256 digest; existing legacy
  invitation rows are not rewritten by this migration. Audit API responses
  additionally omit token-like keys and legacy platform-invite target IDs.
- Audit and license-history rows are append-only. Sensitive database changes
  and their audit events run in one transaction, so an audit failure aborts the
  mutation. Company suspension changes the database authorization context; it
  does not delete data or ban Auth identities.

## Environment setup required before using email invitations

Configure the Edge Function secret `APP_URL` to the HTTPS application origin,
for example `https://pollo-movil-staging.vercel.app`. Supabase Auth must allow
the callback URL `https://pollo-movil-staging.vercel.app/accept-company-invite*`
and the existing password-reset callback. Configure matching callback URLs
for any other environment independently. Local development may use the exact
localhost origin only when the local Auth redirect allow-list permits it.

Email delivery uses Supabase Auth's configured email provider. If it fails, the
company and invitation remain recorded with a safe delivery state so a
platform administrator can retry; no temporary password or raw Auth link is
returned by this console.

## Local verification

The migration is additive and leaves existing customer, license, Auth, and
audit rows in place. Run `platform_console_phase1.test.sql` and the existing
`platform_superadmin_licenses.test.sql` against the local Supabase database.
Do not apply this migration to Staging or production until the project owner
authorizes that separate operation.
