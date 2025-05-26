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
    SELECT ID_reserva INTO v_id_reserva
    FROM reserva
    WHERE id_habitacion = v_id_habitacion
      AND documento_identidad = p_documento_identidad
    ORDER BY ID_reserva DESC
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