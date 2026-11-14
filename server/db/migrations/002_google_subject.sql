-- 002: link a Google account by its Google ID (the token's subject), not only by email.
-- Once linked, the Google ID never changes, so a changed Gmail address still signs in.

ALTER TABLE users ADD COLUMN IF NOT EXISTS google_subject text;

CREATE UNIQUE INDEX IF NOT EXISTS users_google_subject_uq
    ON users (google_subject) WHERE google_subject IS NOT NULL;
