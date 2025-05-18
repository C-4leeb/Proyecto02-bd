create schema sch_reservas_hotel 
set search_path to sch_reservas_hotel

-- Tabla de costos
CREATE TABLE costos (
  id_costos INT PRIMARY KEY, 
  temporada VARCHAR(100),
  promociones_especiales VARCHAR(100)
);

--sexo

-- Tabla de habitación
CREATE TABLE habitacion (
  id_habitacion INT PRIMARY KEY, 
  numero INT NOT NULL,
  id_costos INT,
  FOREIGN KEY (id_costos) REFERENCES costos(id_costos),
  tipo VARCHAR(100) NOT NULL,
  disponibilidad BOOLEAN NOT NULL, 
  descripcion TEXT NOT NULL, 
  caracteristicas TEXT NOT NULL
);

-- Tabla de políticas de reserva
CREATE TABLE politicas_reserva (
  id_politicas SERIAL PRIMARY KEY,
  minimo_noches INT NOT NULL,
  penalizaciones_cancelación VARCHAR(100), 
  upgrades_automaticos BOOLEAN
);

-- Tabla reserva
CREATE TABLE reserva (
  ID_reserva SERIAL PRIMARY KEY,
  numero_huespedes INT NOT NULL,
  id_politicas INT,
  FOREIGN KEY (id_politicas) REFERENCES politicas_reserva(id_politicas),
  id_habitacion INT,
  FOREIGN KEY (id_habitacion) REFERENCES habitacion(id_habitacion)
);

-- Tabla pago
CREATE TABLE pago (
  ID_pago SERIAL PRIMARY KEY,
  tipo_pago VARCHAR(100) NOT NULL,
  plataformas_integradas VARCHAR(100) NOT NULL,
  metodo_pago VARCHAR(100) NOT NULL,
  factura VARCHAR(100) NOT NULL,
  recibo VARCHAR(100),
  reembolso INT,
  cargos_extra VARCHAR(100),
  ID_reserva INT,
  FOREIGN KEY (ID_reserva) REFERENCES reserva(ID_reserva)
);

-- Tabla eventos
CREATE TABLE eventos (
  ID_evento SERIAL PRIMARY KEY,
  habitacion_VIP BOOLEAN NOT NULL,
  bloqueo_por_eventos BOOLEAN NOT NULL,
  grupos BOOLEAN NOT NULL
);

-- Tabla cliente
CREATE TABLE cliente (
  documento_identidad VARCHAR(50) PRIMARY KEY,
  nombre VARCHAR(100),
  nacionalidad VARCHAR(50),
  telefono VARCHAR(20),
  correo VARCHAR(100)
);

--Relacion cliente con reserva
CREATE TABLE cliente_reserva (
  documento_identidad VARCHAR(50) PRIMARY KEY REFERENCES cliente(documento_identidad),
  id_reserva INT REFERENCES reserva (ID_reserva)
);

--Relacion cliente con pago
CREATE TABLE cliente_pago (
  documento_identidad VARCHAR(50) PRIMARY KEY REFERENCES cliente(documento_identidad),
  id_pago INT REFERENCES pago(ID_pago)
  );

-- Tabla servicios
CREATE TABLE servicios (
  id_servicio SERIAL PRIMARY KEY,
  nombre VARCHAR(100),
  disponibilidad BOOLEAN,
  horario TEXT,
  precio DECIMAL(10,2),
  promociones TEXT,
  servicios_extra TEXT,
  ofertas_personalizadas TEXT
);

--Relacion cliente con servicios 
CREATE TABLE cliente_servicio (
  documento_identidad VARCHAR(50) PRIMARY KEY REFERENCES cliente(documento_identidad),
  id_servicio INT REFERENCES servicios(id_servicio)
);

drop table cliente_servicio

-- Tabla programa fidelizacion
CREATE TABLE programa_fidelizacion (
  documento_identidad VARCHAR(50) PRIMARY KEY REFERENCES cliente(documento_identidad),
  nivel_puntos INT,
  nivel_cliente VARCHAR(50),
  beneficios TEXT
);

-- Tabla preferencias
CREATE TABLE preferencias (
  documento_identidad VARCHAR(50) PRIMARY KEY REFERENCES cliente(documento_identidad),
  tipo_habitacion_favorita VARCHAR(50),
  alergias_alimenticias TEXT,
  solicitudes_especiales TEXT
);

