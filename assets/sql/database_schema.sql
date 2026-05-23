

/*
 *Логика статусов:
 * 0 — локально, не для отправки (гость)
 * 1 — в очереди на отправку
 * 2 — успешно отправлено
 * 3 — ошибка отправки
 */
CREATE TABLE observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_uuid TEXT NOT NULL UNIQUE,
  user_login TEXT NOT NULL,
  observed_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  is_manual INTEGER NOT NULL DEFAULT 0,
  accuracy REAL,
  altitude REAL,
  gauss_x REAL,
  gauss_y REAL,
  zone INTEGER,

  status INTEGER NOT NULL DEFAULT 0,
  remote_feature_id INTEGER,
  remote_folder TEXT,
  sync_error TEXT,
  synced_at TEXT,

  deleted_at TEXT,
  schema_version INTEGER NOT NULL DEFAULT 4
);

CREATE TABLE observation_attributes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  observation_id INTEGER NOT NULL,
  attribute_key TEXT NOT NULL,
  value_text TEXT,
  value_number REAL,
  value_bool INTEGER,
  option_id INTEGER,

  created_at TEXT NOT NULL,
  updated_at TEXT,

  FOREIGN KEY (observation_id)
    REFERENCES observations(id)
    ON DELETE CASCADE,

  FOREIGN KEY (option_id)
    REFERENCES attribute_options(id)
    ON DELETE SET NULL,

  UNIQUE(observation_id, attribute_key)
);

/* описываем что такое поле  */
CREATE TABLE attribute_definitions (
  attribute_key TEXT PRIMARY KEY,

  title TEXT NOT NULL,
  value_type TEXT NOT NULL,
  input_type TEXT NOT NULL,

  is_required INTEGER NOT NULL DEFAULT 0,
  is_core INTEGER NOT NULL DEFAULT 0,
  is_synced INTEGER NOT NULL DEFAULT 1,
  allow_custom INTEGER NOT NULL DEFAULT 1,

  hint TEXT,
  dwc_term TEXT,

  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT
);

/* общие списки через сервер */
CREATE TABLE attribute_options (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  attribute_key TEXT NOT NULL,
  value TEXT NOT NULL,
  normalized_value TEXT NOT NULL,

  is_builtin INTEGER NOT NULL DEFAULT 0,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  remote_id INTEGER,
  synced_at TEXT,
  sync_status INTEGER NOT NULL DEFAULT 0,

  FOREIGN KEY (attribute_key)
    REFERENCES attribute_definitions(attribute_key)
    ON DELETE CASCADE,

  UNIQUE(attribute_key, normalized_value)
);

CREATE TABLE IF NOT EXISTS user_resources (
    user_login TEXT PRIMARY KEY,
    user_folder_id INTEGER,
    user_layer_id INTEGER,
    user_style_id INTEGER,
    webmap_id INTEGER,
    updated_at TEXT
);
/*order_index : позволяет воссоздать исходную последовательность */
CREATE TABLE photos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  observation_id INTEGER NOT NULL,
  file_path TEXT,
  uploaded_url TEXT,
  remote_attachment_id INTEGER,
  order_index INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,

  FOREIGN KEY (observation_id)
    REFERENCES observations(id)
    ON DELETE CASCADE
);