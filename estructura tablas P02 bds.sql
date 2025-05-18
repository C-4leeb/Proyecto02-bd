create schema sch_reservas_hotel 
set search_path to sch_reservas_hotel

--todo R
-- Tabla de costos
CREATE TABLE costos (
  id_costos INT PRIMARY KEY, 
  temporada VARCHAR(100),
  promociones_especiales VARCHAR(100)
);


-- Tabla eventos
CREATE TABLE eventos (
  ID_evento SERIAL PRIMARY KEY,
  habitacion_VIP BOOLEAN NOT NULL,
  bloqueo_por_eventos BOOLEAN NOT NULL,
  grupos BOOLEAN NOT NULL
);

-- Tabla de habitación
CREATE TABLE habitacion (
  id_habitacion INT PRIMARY KEY, 
  numero INT NOT NULL,
  id_costos INT,
  FOREIGN KEY (id_costos) REFERENCES costos(id_costos),
  id_evento INT,  
  FOREIGN KEY (id_evento) REFERENCES eventos(ID_evento),
  tipo VARCHAR(100) NOT NULL,
  disponibilidad BOOLEAN NOT NULL, 
  descripcion TEXT NOT NULL, 
  caracteristicas TEXT NOT NULL
);

--Tabla documentos 
CREATE TABLE documentos (
  copia_pasaporte VARCHAR(100) PRIMARY KEY,
  contratos TEXT not null,
  facturacion_electronica TEXT not null
);


--Creando tabla cliente 
CREATE TABLE cliente (
  documento_identidad VARCHAR(50) PRIMARY KEY,
  nombre VARCHAR(100),
  nacionalidad VARCHAR(50),
  telefono VARCHAR(20),
  correo VARCHAR(100),
  ID_pago INT,
  copia_pasaporte VARCHAR(100),
  FOREIGN KEY (copia_pasaporte) REFERENCES documentos(copia_pasaporte)
);

CREATE TABLE programa_fidelizacion (
  documento_identidad VARCHAR(50) PRIMARY KEY,
  nivel_puntos INT NOT NULL,
  nivel_cliente VARCHAR(50) NOT NULL,
  beneficios TEXT NOT NULL,
  FOREIGN KEY (documento_identidad) REFERENCES cliente(documento_identidad)
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
  FOREIGN KEY (id_habitacion) REFERENCES habitacion(id_habitacion),
  documento_identidad VARCHAR(50),
  FOREIGN KEY (documento_identidad) REFERENCES cliente(documento_identidad)
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
--Agregando la relación (1:N) en pago
ALTER TABLE cliente
ADD CONSTRAINT fk_pago
FOREIGN KEY (ID_pago) REFERENCES pago(ID_pago);

-- Tabla servicios
CREATE TABLE servicios (
  id_servicio SERIAL PRIMARY KEY,
  documento_identidad VARCHAR(50) not null,
  nombre VARCHAR(100) not null,
  disponibilidad BOOLEAN not null,
  horario TIME not null,
  precio DECIMAL(10,2) not null,
  promociones TEXT not null,
  servicios_extra TEXT not null,
  ofertas_personalizadas TEXT not null,
  FOREIGN KEY (documento_identidad) REFERENCES cliente (documento_identidad)
);


--Relación 1:1 de clientes con preferencias (En el diagrama lo trabajamos diferente pero revisando nos parece más optimo así)
-- Tabla preferencias
CREATE TABLE preferencias (
  documento_identidad VARCHAR(50) PRIMARY KEY,
  tipo_habitacion_favorita VARCHAR(50) not null,
  alergias_alimenticias TEXT not null,
  solicitudes_especiales TEXT not null,
  FOREIGN KEY (documento_identidad) REFERENCES cliente(documento_identidad)
);