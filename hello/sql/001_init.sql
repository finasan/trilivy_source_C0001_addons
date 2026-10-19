-- hello add-on: one table, proves migrations + the addon_hello datasource
CREATE TABLE IF NOT EXISTS hello_ping (
  id INT AUTO_INCREMENT PRIMARY KEY,
  note VARCHAR(100) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO hello_ping (note) VALUES ('installed by playbook 19');
