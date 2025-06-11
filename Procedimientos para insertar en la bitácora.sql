set search_path to sch_reservas_hotel;

-- Creación de una tabla para registrar eventos importantes sobre las reservaciones.
-- Esto nos permitirá llevar trazabilidad de acciones como creación, cancelación, etc.
CREATE TABLE tabla_log_reservaciones (
    id_log SERIAL PRIMARY KEY, 

    id_reserva INT NOT NULL,   

    accion TEXT NOT NULL,      

    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    
    usuario TEXT,              

    detalle JSONB              
);


CREATE OR REPLACE PROCEDURE registrar_evento_reserva(
    p_id_reserva INT,
    p_accion TEXT,
    p_usuario TEXT,
    p_detalle JSONB
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO tabla_log_reservaciones (id_reserva, accion, usuario, detalle)
    VALUES (p_id_reserva, p_accion, p_usuario, p_detalle);
END;
$$;

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
    v_id_reserva INT;
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

    -- Obtener el ID de la reserva recién creada
    SELECT id_reserva INTO v_id_reserva
	FROM reserva
	WHERE id_habitacion = v_id_habitacion
	  AND documento_identidad = p_documento_identidad
	ORDER BY id_reserva DESC
	LIMIT 1;
    -- Registrar en la bitácora
    CALL registrar_evento_reserva(
        v_id_reserva,
        'creación de reserva',
        p_documento_identidad,
        jsonb_build_object(
            'tipo_reserva', p_tipo_reserva,
            'tipo_confirmacion', p_tipo_confirmacion,
            'fecha_entrada', p_fecha_entrada,
            'fecha_salida', p_fecha_salida,
            'solicitudes', p_solicitudes_especial
        )
    );

    RAISE NOTICE 'Reserva creada exitosamente en habitacion %', v_id_habitacion;
END;
$$;


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
	CALL registrar_evento_reserva(
    p_id_reserva,
    'cancelación de reserva',
    'sistema', -- o puedes pasar un parámetro si deseas registrar el usuario real
    jsonb_build_object(
        'accion', 'Reserva cancelada',
        'habitacion_liberada', v_id_habitacion
    )
);
END;
$$;


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

    -- Registrar en la bitácora
    CALL registrar_evento_reserva(
        p_id_reserva,
        'confirmación de pago',
        'sistema',
        jsonb_build_object(
            'mensaje', 'Pago registrado y reserva confirmada'
        )
    );

    RAISE NOTICE 'Reserva % confirmada.', p_id_reserva;
END;
$$;


CREATE OR REPLACE FUNCTION log_eliminacion_reserva()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO tabla_log_reservaciones (id_reserva, accion, usuario, detalle)
    VALUES (
        OLD.id_reserva,
        'DELETE',
        current_user,
        to_jsonb(OLD)
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_delete_reserva
BEFORE DELETE ON reserva
FOR EACH ROW
EXECUTE FUNCTION log_eliminacion_reserva();


CREATE OR REPLACE PROCEDURE restaurar_reservas_desde_bitacora(
    p_id_reserva INT DEFAULT NULL  -- Si no se indica, se restauran todas
)
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT * 
        FROM tabla_log_reservaciones
        WHERE accion = 'DELETE'
          AND (p_id_reserva IS NULL OR id_reserva = p_id_reserva)
        ORDER BY fecha_hora
    LOOP
        -- Verificar que la reserva no exista antes de insertarla
        IF NOT EXISTS (
            SELECT 1 FROM reserva WHERE id_reserva = (r.detalle->>'id_reserva')::INT
        ) THEN
            INSERT INTO reserva (
                id_reserva, numero_huespedes, solicitudes_especial,
                tipo_reserva, tipo_confirmacion, fecha_entrada,
                fecha_salida, id_politicas, id_habitacion,
                documento_identidad, estado_reserva
            )
            SELECT
                (r.detalle->>'id_reserva')::INT,
                (r.detalle->>'numero_huespedes')::INT,
                r.detalle->>'solicitudes_especial',
                r.detalle->>'tipo_reserva',
                r.detalle->>'tipo_confirmacion',
                (r.detalle->>'fecha_entrada')::DATE,
                (r.detalle->>'fecha_salida')::DATE,
                (r.detalle->>'id_politicas')::INT,
                (r.detalle->>'id_habitacion')::INT,
                r.detalle->>'documento_identidad',
                r.detalle->>'estado_reserva';
                
            RAISE NOTICE 'Reserva % restaurada.', (r.detalle->>'id_reserva')::INT;
        ELSE
            RAISE NOTICE 'Reserva % ya existe. No se restauró.', (r.detalle->>'id_reserva')::INT;
        END IF;
    END LOOP;
END;
$$;

--PRUEBA PREVIA:

-- Insertar documentos
INSERT INTO sch_reservas_hotel.documentos (copia_pasaporte, contratos, facturacion_electronica)
VALUES ('DOC123', 'Contrato estándar', 'Factura estándar');

-- Insertar cliente
INSERT INTO sch_reservas_hotel.cliente (documento_identidad, nombre, nacionalidad, telefono, correo, ID_pago, copia_pasaporte)
VALUES ('CLI001', 'Ana Pérez', 'Costa Rica', '8888-0000', 'ana@example.com', NULL, 'DOC123');

-- Insertar política
INSERT INTO sch_reservas_hotel.politicas_reserva (minimo_noches, penalizaciones_cancelación, upgrades_automaticos)
VALUES (1, 'Sin penalización', FALSE);

-- Insertar costo y evento
INSERT INTO sch_reservas_hotel.costos (id_costos, temporada, promociones_especiales)
VALUES (10, 'Alta', 'Ninguna');

INSERT INTO sch_reservas_hotel.eventos (habitacion_VIP, bloqueo_por_eventos, grupos)
VALUES (FALSE, FALSE, FALSE);

-- Insertar habitación
INSERT INTO sch_reservas_hotel.habitacion (
  id_habitacion, numero, id_costos, id_evento, tipo, disponibilidad, descripcion, caracteristicas
)
VALUES (
  100, 101, 10, 1, 'doble', 'libre', 'Habitación doble con aire acondicionado', 'TV, WiFi, Aire'
);

INSERT INTO sch_reservas_hotel.habitacion (
  id_habitacion, numero, id_costos, id_evento, tipo, disponibilidad, descripcion, caracteristicas
)
VALUES 
  (101, 102, 10, 1, 'doble', 'libre', 'Habitación doble con balcón', 'Balcón, WiFi, Minibar'),
  (102, 103, 10, 1, 'doble', 'libre', 'Habitación doble económica', 'WiFi, Ventilador');

CALL crear_reservacion(
  2,
  'doble',
  1,
  'CLI001',
  CURRENT_DATE,
  (CURRENT_DATE + INTERVAL '2 day')::DATE,
  'individual',
  'correo',
  'Cerca del elevador'
);

CALL crear_reservacion(
  1,
  'doble',
  1,
  'CLI001',
  (CURRENT_DATE + INTERVAL '3 day')::DATE,
  (CURRENT_DATE + INTERVAL '5 day')::DATE,
  'grupo', 
  'correo',  
  'Lejos del ascensor'
);

CALL crear_reservacion(
  3,
  'doble',
  1,
  'CLI001',
  (CURRENT_DATE + INTERVAL '7 day')::DATE,
  (CURRENT_DATE + INTERVAL '10 day')::DATE,
  'corporativa', 
  'teléfono',     
  'Sin solicitudes'
);

SELECT * FROM reserva ORDER BY id_reserva;
--Por si se llegara a eliminar las reservaciones:
-- Eliminar la reservaciones se activa el trigger de bitácora
DELETE FROM reserva;

-- seleccion de lo que se elimino desde la Bitacora
SELECT * FROM tabla_log_reservaciones WHERE accion = 'DELETE';

--Se restaura lo que se solo la reservacion con id 1
CALL restaurar_reservas_desde_bitacora(1);


SELECT * FROM reserva 

--Para restaurar todo 
CALL restaurar_reservas_desde_bitacora();
