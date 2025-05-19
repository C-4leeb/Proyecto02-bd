set search_path to sch_reservas_hotel


CREATE OR REPLACE PROCEDURE disponibilidad_habitaciones()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Marcar habitaciones con eventos activos
    UPDATE habitacion h
    SET disponibilidad = 'ocupada'
    FROM eventos e
    WHERE h.id_evento = e.ID_evento
      AND (e.bloqueo_por_eventos = TRUE OR e.grupos = TRUE);

    -- Marcar habitaciones con reserva activa
    UPDATE habitacion
    SET disponibilidad = 'ocupada'
    WHERE id_habitacion IN (
        SELECT id_habitacion FROM reserva
    );

    -- Marcar habitaciones VIP sin reservas como 'libre'
    UPDATE habitacion h
    SET disponibilidad = 'libre'
    FROM eventos e
    WHERE h.id_evento = e.ID_evento
      AND e.habitacion_VIP = TRUE
      AND h.id_habitacion NOT IN (SELECT id_habitacion FROM reserva)
      AND h.disponibilidad NOT IN ('en mantenimiento', 'ocupada');

    -- Marcar otras habitaciones libres (que no están reservadas ni ocupadas)
    UPDATE habitacion
    SET disponibilidad = 'libre'
    WHERE id_habitacion NOT IN (SELECT id_habitacion FROM reserva)
      AND disponibilidad NOT IN ('en mantenimiento', 'ocupada');
END;
$$;


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


CREATE OR REPLACE PROCEDURE cancelar_reservacion(p_id_reserva INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_habitacion INT;
BEGIN
    -- Obtener la habitacion asociada a la reserva
    SELECT id_habitacion INTO v_id_habitacion
    FROM reserva
    WHERE ID_reserva = p_id_reserva;

    -- Verificar si la reserva existe
    IF v_id_habitacion IS NULL THEN
        RAISE EXCEPTION 'No se encontró una reserva con el ID %', p_id_reserva;
    END IF;

    -- Eliminar pagos asociados si los hay 
    DELETE FROM pago WHERE ID_reserva = p_id_reserva;

    -- Liberar la habitación
    UPDATE habitacion
    SET disponibilidad = 'libre'
    WHERE id_habitacion = v_id_habitacion;

    -- Eliminar la reserva
    DELETE FROM reserva
    WHERE ID_reserva = p_id_reserva;

    RAISE NOTICE 'Reserva % cancelada, p_id_reserva';
END;
$$;

-- Cambia el estado de la reservación una vez registrado el pago realizado
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