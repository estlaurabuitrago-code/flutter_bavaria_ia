-- Borrar en orden correcto (primero la que tiene referencias)
DROP TABLE IF EXISTS reporte;
DROP TABLE IF EXISTS opm;
DROP TABLE IF EXISTS usuario;
DROP TABLE IF EXISTS maquina;

-- Tabla de máquinas
CREATE TABLE maquina (
  id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL,
  ubicacion TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Tabla de usuarios
CREATE TABLE usuario (
  id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL,
  email TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  foto_url TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Evita registrar dos veces el mismo correo (comparación sin distinguir mayúsculas/minúsculas)
CREATE UNIQUE INDEX usuario_email_unique ON usuario (lower(email));

-- Tabla de reportes
CREATE TABLE reporte (
  id SERIAL PRIMARY KEY,
  usuario_id INTEGER REFERENCES usuario(id),
  maquina_id INTEGER REFERENCES maquina(id),
  foto_rayon_url TEXT,
  confianza DECIMAL(4,3),
  cantidad_rayones INTEGER DEFAULT 0,
  fecha_hora TIMESTAMP DEFAULT NOW(),
  observaciones TEXT
);

-- Máquinas reales de Bavaria Tocancipá
INSERT INTO maquina (nombre, ubicacion) VALUES
('776', 'Planta Tocancipá'),
('713', 'Planta Tocancipá'),
('712', 'Planta Tocancipá'),
('718', 'Planta Tocancipá'),
('725', 'Planta Tocancipá'),
('721', 'Planta Tocancipá'),
('711', 'Planta Tocancipá'),
('705', 'Planta Tocancipá'),
('707', 'Planta Tocancipá'),
('675', 'Planta Tocancipá'),
('709', 'Planta Tocancipá'),
('732', 'Planta Tocancipá'),
('724', 'Planta Tocancipá'),
('703', 'Planta Tocancipá'),
('728', 'Planta Tocancipá'),
('890', 'Planta Tocancipá'),
('738', 'Planta Tocancipá'),
('529', 'Planta Tocancipá'),
('706', 'Planta Tocancipá'),
('538', 'Planta Tocancipá'),
('671', 'Planta Tocancipá'),
('617', 'Planta Tocancipá'),
('701', 'Planta Tocancipá'),
('555', 'Planta Tocancipá'),
('722', 'Planta Tocancipá'),
('333', 'Planta Tocancipá'),
('726', 'Planta Tocancipá'),
('702', 'Planta Tocancipá'),
('678', 'Planta Tocancipá'),
('777', 'Planta Tocancipá'),
('714', 'Planta Tocancipá'),
('741', 'Planta Tocancipá'),
('889', 'Planta Tocancipá'),
('733', 'Planta Tocancipá'),
('677', 'Planta Tocancipá'),
('710', 'Planta Tocancipá'),
('552', 'Planta Tocancipá'),
('626', 'Planta Tocancipá'),
('CE-1', 'Planta Tocancipá'),
('814', 'Planta Tocancipá'),
('811', 'Planta Tocancipá'),
('812', 'Planta Tocancipá'),
('813', 'Planta Tocancipá'),
('704', 'Planta Tocancipá'),
('820', 'Planta Tocancipá'),
('CE-2', 'Planta Tocancipá'),
('792', 'Planta Tocancipá'),
('830', 'Planta Tocancipá'),
('582', 'Planta Tocancipá'),
('591', 'Planta Tocancipá'),
('866', 'Planta Tocancipá'),
('868', 'Planta Tocancipá'),
('BT1', 'Planta Tocancipá'),
('691', 'Planta Tocancipá'),
('577', 'Planta Tocancipá'),
('581', 'Planta Tocancipá'),
('692', 'Planta Tocancipá'),
('315', 'Planta Tocancipá'),
('867', 'Planta Tocancipá'),
('731', 'Planta Tocancipá'),
('879', 'Planta Tocancipá'),
('576', 'Planta Tocancipá'),
('821', 'Planta Tocancipá'),
('383', 'Planta Tocancipá'),
('546', 'Planta Tocancipá'),
('828', 'Planta Tocancipá'),
('AT35', 'Planta Tocancipá'),
('AT02', 'Planta Tocancipá'),
('881', 'Planta Tocancipá'),
('871', 'Planta Tocancipá'),
('853', 'Planta Tocancipá'),
('884', 'Planta Tocancipá'),
('888', 'Planta Tocancipá'),
('535', 'Planta Tocancipá'),
('A4448', 'Planta Tocancipá'),
('674', 'Planta Tocancipá'),
('589', 'Planta Tocancipá');

-- Al final del script, después de los INSERTs:
ALTER TABLE maquina DISABLE ROW LEVEL SECURITY;
ALTER TABLE usuario DISABLE ROW LEVEL SECURITY;
ALTER TABLE reporte DISABLE ROW LEVEL SECURITY;
