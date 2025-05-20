set search_path to sch_reservas_hotel


--PRUEBA DE Procedimiento para verificar disponibilidad de habitaciones automáticamente.
-- Costos
INSERT INTO costos (id_costos, temporada, promociones_especiales)
VALUES (1, 'Alta', 'Ninguna');

-- Eventos
INSERT INTO eventos (habitacion_VIP, bloqueo_por_eventos, grupos)
VALUES
  (FALSE, TRUE, FALSE),  -- Evento 1: bloqueo por evento
  (FALSE, FALSE, TRUE),  -- Evento 2: evento de grupo
  (TRUE, FALSE, FALSE);  -- Evento 3: VIP sin bloqueo ni grupo

-- Habitaciones
INSERT INTO habitacion (id_habitacion, numero, id_costos, id_evento, tipo, disponibilidad, descripcion, caracteristicas)
VALUES
  (101, 1, 1, 1, 'sencilla', 'libre', 'Habitación con evento bloqueo', 'TV, Wi-Fi'),
  (102, 2, 1, 2, 'doble', 'libre', 'Habitación con evento grupo', 'TV, Balcón'),
  (103, 3, 1, NULL, 'suite', 'libre', 'Habitación reservada', 'Jacuzzi, Wi-Fi'),
  (104, 4, 1, 3, 'suite', 'libre', 'Habitación VIP sin reservas', 'Jacuzzi, Vista al mar'),
  (105, 5, 1, NULL, 'doble', 'ocupada', 'Habitación libre sin eventos ni reservas', 'TV, Wi-Fi'),
  (106, 6, 1, NULL, 'doble', 'en mantenimiento', 'Habitación en mantenimiento', 'TV, Wi-Fi');

-- Documentos
INSERT INTO documentos (copia_pasaporte, contratos, facturacion_electronica)
VALUES ('X123', 'Contrato A', 'Factura A');

-- Cliente
INSERT INTO cliente (documento_identidad, nombre, nacionalidad, telefono, correo, ID_pago, copia_pasaporte)
VALUES ('C001', 'Ana Perez', 'Costa Rica', '8888-0000', 'ana@example.com', NULL, 'X123');

-- Políticas
INSERT INTO politicas_reserva (minimo_noches, penalizaciones_cancelación, upgrades_automaticos)
VALUES (2, '25% antes de 48h', TRUE);

-- Reserva confirmada para la habitación 103
INSERT INTO reserva (
  numero_huespedes, solicitudes_especial, tipo_reserva, tipo_confirmacion,
  fecha_entrada, fecha_salida, id_politicas, id_habitacion,
  documento_identidad, estado_reserva
)
VALUES (
  2, 'Cama adicional', 'grupo', 'correo',
  CURRENT_DATE, CURRENT_DATE + 2, 1, 103,
  'C001', 'Confirmada'
);

--Procedimiento para verificar disponibilidad de habitaciones automáticamente.
CREATE OR REPLACE PROCEDURE disponibilidad_habitaciones()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Marcar todas libre al inicio
    UPDATE habitacion
    SET disponibilidad = 'libre'
    WHERE disponibilidad <> 'en mantenimiento';

    -- Marcar como ocupada si tiene eventos activos 
    UPDATE habitacion h
    SET disponibilidad = 'ocupada'
    FROM eventos e
    WHERE h.id_evento = e.ID_evento
      AND (e.bloqueo_por_eventos = TRUE OR e.grupos = TRUE);

    -- 3. Marcar como ocupad' si tiene reserva confirmada
    UPDATE habitacion h
    SET disponibilidad = 'ocupada'
    FROM reserva r
    WHERE h.id_habitacion = r.id_habitacion
      AND r.estado_reserva = 'Confirmada';

    -- Asegurar que habitaciones VIP sin reservas ni eventos queden libres
    UPDATE habitacion h
    SET disponibilidad = 'libre'
    FROM eventos e
    WHERE h.id_evento = e.ID_evento
      AND e.habitacion_VIP = TRUE
      AND h.id_habitacion NOT IN (
          SELECT r.id_habitacion FROM reserva r WHERE r.estado_reserva = 'Confirmada'
      )
      AND h.id_habitacion NOT IN (
          SELECT h2.id_habitacion
          FROM habitacion h2
          JOIN eventos e2 ON h2.id_evento = e2.ID_evento
          WHERE e2.bloqueo_por_eventos = TRUE OR e2.grupos = TRUE
      )
      AND h.disponibilidad NOT IN ('en mantenimiento', 'ocupada');
END;
$$;

CALL disponibilidad_habitaciones();

SELECT id_habitacion, numero, disponibilidad, descripcion
FROM habitacion
ORDER BY id_habitacion;


--Procedimiento para crear nueva reservación
CREATE OR REPLACE PROCEDURE crear_reservacion(
    p_numero_huespedes INT,
    p_tipo_habitacion VARCHAR,
    p_id_politicas INT,
    p_documento_identidad VARCHAR,
    p_fecha_entrada DATE,
    p_fecha_salida DATE,
    p_tipo_reserva VARCHAR,
    p_tipo_confirmacion VARCHAR,
    p_solicitudes_especial TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_habitacion INT;
BEGIN
    -- Buscar una habitacion libre del tipo solicitado
    SELECT id_habitacion INTO v_id_habitacion
    FROM habitacion
    WHERE tipo = p_tipo_habitacion
      AND disponibilidad = 'libre'
    LIMIT 1;

    -- Si no hay habitaciones disponibles, lanzar error
    IF v_id_habitacion IS NULL THEN
        RAISE EXCEPTION 'No hay habitaciones disponibles de tipo %', p_tipo_habitacion;
    END IF;

    -- Insertar la nueva reserva
    INSERT INTO reserva(
        numero_huespedes, 
        solicitudes_especial,
        tipo_reserva,
        tipo_confirmacion,
        fecha_entrada,
        fecha_salida,
        id_politicas, 
        id_habitacion, 
        documento_identidad
    )
    VALUES (
        p_numero_huespedes, 
        p_solicitudes_especial,
        p_tipo_reserva,
        p_tipo_confirmacion,
        p_fecha_entrada,
        p_fecha_salida,
        p_id_politicas, 
        v_id_habitacion, 
        p_documento_identidad
    );

    -- Marcar habitacion como ocupada
    UPDATE habitacion
    SET disponibilidad = 'ocupada'
    WHERE id_habitacion = v_id_habitacion;

    RAISE NOTICE 'Reserva creada exitosamente en habitacion %', v_id_habitacion;
END;
$$;


--PRUEBA PROCEDIMIENTO CREAR RESERVACION 

INSERT INTO sch_reservas_hotel.documentos (copia_pasaporte, contratos, facturacion_electronica)
VALUES ('X999', 'Contrato B', 'Factura B');

INSERT INTO sch_reservas_hotel.cliente (documento_identidad, nombre, nacionalidad, telefono, correo, ID_pago, copia_pasaporte)
VALUES ('C999', 'Carlos Ruiz', 'Costa Rica', '8888-9999', 'carlos@example.com', NULL, 'X999');

INSERT INTO sch_reservas_hotel.politicas_reserva (minimo_noches, penalizaciones_cancelación, upgrades_automaticos)
VALUES (1, 'No aplica', FALSE);


CALL sch_reservas_hotel.crear_reservacion(
    p_numero_huespedes := 2,
    p_tipo_habitacion := 'doble',
    p_id_politicas := 1,
    p_documento_identidad := 'C999',
    p_fecha_entrada := CURRENT_DATE,
    p_fecha_salida := CURRENT_DATE + 2,
    p_tipo_reserva := 'individual',
    p_tipo_confirmacion := 'correo',
    p_solicitudes_especial := 'Cama adicional'
);


SELECT * 
FROM sch_reservas_hotel.reserva
WHERE documento_identidad = 'C999'


--Procedimiento para cancerlar una reservacion
CREATE OR REPLACE PROCEDURE cancelar_reservacion(p_id_reserva INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_habitacion INT;
BEGIN
    -- Verificar si la reserva existe y obtener la habitacion
    SELECT id_habitacion INTO v_id_habitacion
    FROM reserva
    WHERE ID_reserva = p_id_reserva;

    IF v_id_habitacion IS NULL THEN
        RAISE EXCEPTION 'No se encontro una reserva con el ID %', p_id_reserva;
    END IF;

    -- Eliminar pagos asociados 
    DELETE FROM pago WHERE ID_reserva = p_id_reserva;

    -- Marcar la reserva como cancelada
    UPDATE reserva
    SET estado_reserva = 'Cancelada'
    WHERE ID_reserva = p_id_reserva;

    -- Liberar la habitacion 
    UPDATE habitacion
    SET disponibilidad = 'libre'
    WHERE id_habitacion = v_id_habitacion;

 
    RAISE NOTICE 'Reserva % cancelada.', p_id_reserva;
END;
$$;

--PRUEBA para cancelar la reservacion que se creo ahora:

CALL sch_reservas_hotel.cancelar_reservacion(4); --Es con el ID de la reservacion por aquello 

--Procedimieto que cambia el estado de la reservación una vez registrado el pago realizado
CREATE OR REPLACE PROCEDURE ActualizarEstadoPago(p_id_reserva INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pago_existente INT;
BEGIN
    -- Verificar si existe el pago 
    SELECT COUNT(*) INTO v_pago_existente
    FROM pago
    WHERE ID_reserva = p_id_reserva;

    -- Si no hay pago, lanzar excepción
    IF v_pago_existente = 0 THEN
        RAISE EXCEPTION 'No hay un pago registrado para la reserva %', p_id_reserva;
    END IF;

    -- Actualizar estado de la reserva a Confirmada
    UPDATE reserva
    SET estado_reserva = 'Confirmada'
    WHERE ID_reserva = p_id_reserva;

    RAISE NOTICE 'Reserva % confirmada.', p_id_reserva;
END;
$$;

--Prueba DE PROCEDIMEITNO PAGO

-- Documento
INSERT INTO sch_reservas_hotel.documentos (copia_pasaporte, contratos, facturacion_electronica)
VALUES ('XPAY', 'Contrato pago', 'Factura digital') 
ON CONFLICT DO NOTHING;

-- Cliente
INSERT INTO sch_reservas_hotel.cliente (
  documento_identidad, nombre, nacionalidad, telefono, correo, ID_pago, copia_pasaporte
)
VALUES ('P001', 'Pedro Soto', 'Costa Rica', '8888-1111', 'pedro@correo.com', NULL, 'XPAY')
ON CONFLICT DO NOTHING;


--VOY A CREAR UNA RESERVA CON EL PROCEDIMEINTO ;p

CALL sch_reservas_hotel.crear_reservacion(
    p_numero_huespedes := 2,
    p_tipo_habitacion := 'doble',
    p_id_politicas := 1,  
    p_documento_identidad := 'P001',
    p_fecha_entrada := CURRENT_DATE,
    p_fecha_salida := CURRENT_DATE + 2,
    p_tipo_reserva := 'individual',
    p_tipo_confirmacion := 'correo',
    p_solicitudes_especial := 'Pago en efectivo'
);

SELECT ID_reserva, estado_reserva
FROM sch_reservas_hotel.reserva
WHERE documento_identidad = 'P001'
ORDER BY ID_reserva DESC
LIMIT 1;

INSERT INTO sch_reservas_hotel.pago (
  tipo_pago, plataformas_integradas, metodo_pago, factura, recibo, reembolso, cargos_extra, ID_reserva
)
VALUES (
  'efectivo', 'N/A', 'pago directo', 'FACT-001', 'REC-001', 0, 'Ninguno', 5
);

CALL sch_reservas_hotel.ActualizarEstadoPago(5);

SELECT ID_reserva, estado_reserva
FROM sch_reservas_hotel.reserva
WHERE ID_reserva = 5;