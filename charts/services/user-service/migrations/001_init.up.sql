CREATE TYPE sex AS ENUM ('male', 'female');

CREATE TABLE IF NOT EXISTS cities (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    -- UUIDv7 is generated in application layer.
    id UUID PRIMARY KEY,
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    birth_date DATE NOT NULL,
    bio VARCHAR(500),
    toiler_score SMALLINT NOT NULL CHECK (toiler_score BETWEEN 1 AND 10),
    alcohol_info VARCHAR(120),
    smoking_info VARCHAR(120),
    sex sex NOT NULL,
    height_cm SMALLINT CHECK (height_cm BETWEEN 100 AND 260),
    city_id BIGINT REFERENCES cities(id) ON DELETE SET NULL,
    primary_photo_object_key TEXT NOT NULL,
    primary_photo_url TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_photos (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL,
    url TEXT NOT NULL,
    position SMALLINT NOT NULL CHECK (position BETWEEN 1 AND 6),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, position),
    UNIQUE (user_id, object_key)
);

CREATE INDEX IF NOT EXISTS idx_users_city_id ON users(city_id);
CREATE INDEX IF NOT EXISTS idx_users_birth_date ON users(birth_date);
CREATE INDEX IF NOT EXISTS idx_user_photos_user_id ON user_photos(user_id);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_set_updated_at ON users;
CREATE TRIGGER trg_users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


