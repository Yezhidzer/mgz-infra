DROP TRIGGER IF EXISTS trg_users_set_updated_at ON users;
DROP FUNCTION IF EXISTS set_updated_at();

DROP INDEX IF EXISTS idx_user_photos_user_id;
DROP INDEX IF EXISTS idx_users_birth_date;
DROP INDEX IF EXISTS idx_users_city_id;

DROP TABLE IF EXISTS user_photos;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS cities;

DROP TYPE IF EXISTS sex;


