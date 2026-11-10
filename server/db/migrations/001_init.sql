-- Gharbaar Phase 1 schema (PostgreSQL 16)
-- Rules enforced here: username and email cannot be changed once set,
-- and a household always keeps at least one active head.

CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username        text,
    email           text,
    phone           text,
    password_hash   text,
    is_super_admin  boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_has_identifier CHECK (username IS NOT NULL OR email IS NOT NULL OR phone IS NOT NULL),
    CONSTRAINT users_username_lower CHECK (username IS NULL OR username = lower(username))
);
CREATE UNIQUE INDEX users_username_uq ON users (username) WHERE username IS NOT NULL;
CREATE UNIQUE INDEX users_email_uq    ON users (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_phone_uq    ON users (phone) WHERE phone IS NOT NULL;

CREATE TABLE user_profiles (
    user_id       uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    display_name  text NOT NULL DEFAULT '',
    currency      text NOT NULL DEFAULT 'PKR',
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash  text NOT NULL UNIQUE,
    device      text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz
);

-- A username and a linked Gmail address cannot be changed once set.
CREATE FUNCTION forbid_identifier_change() RETURNS trigger AS $$
BEGIN
    IF OLD.username IS NOT NULL AND NEW.username IS DISTINCT FROM OLD.username THEN
        RAISE EXCEPTION 'username cannot be changed once created';
    END IF;
    IF OLD.email IS NOT NULL AND NEW.email IS DISTINCT FROM OLD.email THEN
        RAISE EXCEPTION 'linked email cannot be changed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_identifiers_locked
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION forbid_identifier_change();

CREATE TABLE households (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    created_by  uuid NOT NULL REFERENCES users (id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);

-- Roles per household. A removed member's row stays for history (left_at is set).
CREATE TABLE household_members (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households (id),
    user_id     uuid NOT NULL REFERENCES users (id),
    role        text NOT NULL CHECK (role IN ('head', 'member')),
    joined_at   timestamptz NOT NULL DEFAULT now(),
    left_at     timestamptz,
    removed_by  uuid REFERENCES users (id)
);
CREATE UNIQUE INDEX household_members_active_uq
    ON household_members (household_id, user_id) WHERE left_at IS NULL;

-- Every household with active members must keep at least one active head.
CREATE FUNCTION ensure_household_has_head() RETURNS trigger AS $$
DECLARE
    hid uuid := COALESCE(NEW.household_id, OLD.household_id);
BEGIN
    IF EXISTS (
        SELECT 1 FROM household_members WHERE household_id = hid AND left_at IS NULL
    ) AND NOT EXISTS (
        SELECT 1 FROM household_members WHERE household_id = hid AND left_at IS NULL AND role = 'head'
    ) THEN
        RAISE EXCEPTION 'household % must keep at least one head', hid;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER household_members_keep_head
    AFTER INSERT OR UPDATE OR DELETE ON household_members
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION ensure_household_has_head();

-- Permissions granted by a head, per module (Phase 1: budget).
CREATE TABLE member_permissions (
    household_id  uuid NOT NULL REFERENCES households (id),
    user_id       uuid NOT NULL REFERENCES users (id),
    module        text NOT NULL,
    can_view      boolean NOT NULL DEFAULT false,
    can_edit      boolean NOT NULL DEFAULT false,
    granted_by    uuid REFERENCES users (id),
    PRIMARY KEY (household_id, user_id, module)
);

-- Join requests. Target is a username, Gmail address or phone number (normalised).
CREATE TABLE invites (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  uuid NOT NULL REFERENCES households (id),
    invited_by    uuid NOT NULL REFERENCES users (id),
    target_type   text NOT NULL CHECK (target_type IN ('username', 'gmail', 'phone')),
    target_value  text NOT NULL,
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    responded_at  timestamptz
);
CREATE UNIQUE INDEX invites_pending_uq
    ON invites (household_id, target_type, target_value) WHERE status = 'pending';

-- Budget categories and expenses. Changes are versioned, deletes are soft.
CREATE TABLE budget_categories (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   uuid NOT NULL REFERENCES households (id),
    name           text NOT NULL,
    monthly_limit  numeric(14, 2) NOT NULL CHECK (monthly_limit > 0),
    version        integer NOT NULL DEFAULT 1,
    created_by     uuid NOT NULL REFERENCES users (id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    deleted_at     timestamptz
);

CREATE TABLE expenses (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  uuid NOT NULL REFERENCES households (id),
    category_id   uuid REFERENCES budget_categories (id),
    amount        numeric(14, 2) NOT NULL CHECK (amount > 0),
    expense_date  date NOT NULL,
    note          text,
    source        text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'ai_suggested')),
    version       integer NOT NULL DEFAULT 1,
    created_by    uuid NOT NULL REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    deleted_at    timestamptz
);
CREATE INDEX expenses_household_date_idx ON expenses (household_id, expense_date);

-- Sync conflicts: a change based on an old version is kept here for the user to decide.
CREATE TABLE sync_conflicts (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    uuid NOT NULL REFERENCES households (id),
    entity          text NOT NULL,
    entity_id       uuid NOT NULL,
    client_version  integer NOT NULL,
    server_version  integer NOT NULL,
    client_data     jsonb NOT NULL,
    status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Every change, used for the sync feed and the audit trail.
CREATE TABLE change_log (
    id            bigserial PRIMARY KEY,
    household_id  uuid NOT NULL REFERENCES households (id),
    entity        text NOT NULL,
    entity_id     uuid NOT NULL,
    operation     text NOT NULL CHECK (operation IN ('create', 'update', 'delete')),
    payload       jsonb,
    actor         uuid REFERENCES users (id),
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX change_log_household_idx ON change_log (household_id, id);
