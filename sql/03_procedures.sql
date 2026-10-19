-- =============================================================
-- Operações do dia a dia da oficina
-- =============================================================

USE oficina;

DELIMITER //

CREATE PROCEDURE sp_abrir_os(
    IN  p_placa       VARCHAR(8),
    IN  p_mecanico_id INT UNSIGNED,
    IN  p_km          INT UNSIGNED,
    IN  p_observacoes VARCHAR(500),
    OUT p_os_id       INT UNSIGNED)
BEGIN
    DECLARE v_veiculo_id INT UNSIGNED;
    DECLARE v_ativo BOOLEAN;

    -- Aceita a placa com ou sem hífen e em minúsculas
    SELECT id INTO v_veiculo_id FROM veiculos WHERE placa = UPPER(REPLACE(p_placa, '-', ''));
    IF v_veiculo_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veiculo nao cadastrado';
    END IF;

    SELECT ativo INTO v_ativo FROM mecanicos WHERE id = p_mecanico_id;
    IF v_ativo IS NULL OR NOT v_ativo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mecanico inexistente ou inativo';
    END IF;

    IF EXISTS (SELECT 1 FROM ordens_servico
                WHERE veiculo_id = v_veiculo_id AND status IN ('aberta', 'em_andamento')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veiculo ja possui ordem de servico em aberto';
    END IF;

    IF p_km < (SELECT COALESCE(MAX(km_entrada), 0) FROM ordens_servico
                WHERE veiculo_id = v_veiculo_id AND status <> 'cancelada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quilometragem menor que a registrada na ultima visita';
    END IF;

    INSERT INTO ordens_servico (veiculo_id, mecanico_id, km_entrada, observacoes)
    VALUES (v_veiculo_id, p_mecanico_id, p_km, p_observacoes);

    SET p_os_id = LAST_INSERT_ID();
END //

CREATE PROCEDURE sp_adicionar_servico(
    IN p_os_id      INT UNSIGNED,
    IN p_servico_id INT UNSIGNED,
    IN p_quantidade SMALLINT UNSIGNED)
BEGIN
    DECLARE v_preco DECIMAL(10, 2);

    SELECT preco INTO v_preco FROM servicos WHERE id = p_servico_id;
    IF v_preco IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Servico nao encontrado';
    END IF;

    IF EXISTS (SELECT 1 FROM os_servicos WHERE os_id = p_os_id AND servico_id = p_servico_id) THEN
        UPDATE os_servicos SET quantidade = quantidade + p_quantidade
         WHERE os_id = p_os_id AND servico_id = p_servico_id;
    ELSE
        INSERT INTO os_servicos (os_id, servico_id, quantidade, preco_unitario)
        VALUES (p_os_id, p_servico_id, p_quantidade, v_preco);
    END IF;

    -- O primeiro item lançado coloca a OS em andamento
    UPDATE ordens_servico SET status = 'em_andamento' WHERE id = p_os_id AND status = 'aberta';
END //

CREATE PROCEDURE sp_adicionar_peca(
    IN p_os_id      INT UNSIGNED,
    IN p_peca_id    INT UNSIGNED,
    IN p_quantidade SMALLINT UNSIGNED)
BEGIN
    DECLARE v_preco DECIMAL(10, 2);

    SELECT preco INTO v_preco FROM pecas WHERE id = p_peca_id;
    IF v_preco IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Peca nao encontrada';
    END IF;

    IF EXISTS (SELECT 1 FROM os_pecas WHERE os_id = p_os_id AND peca_id = p_peca_id) THEN
        UPDATE os_pecas SET quantidade = quantidade + p_quantidade
         WHERE os_id = p_os_id AND peca_id = p_peca_id;
    ELSE
        INSERT INTO os_pecas (os_id, peca_id, quantidade, preco_unitario)
        VALUES (p_os_id, p_peca_id, p_quantidade, v_preco);
    END IF;

    UPDATE ordens_servico SET status = 'em_andamento' WHERE id = p_os_id AND status = 'aberta';
END //

CREATE PROCEDURE sp_remover_peca(IN p_os_id INT UNSIGNED, IN p_peca_id INT UNSIGNED)
BEGIN
    DELETE FROM os_pecas WHERE os_id = p_os_id AND peca_id = p_peca_id;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Peca nao faz parte desta ordem de servico';
    END IF;
END //

CREATE PROCEDURE sp_concluir_os(IN p_os_id INT UNSIGNED)
BEGIN
    CALL sp_validar_os_editavel(p_os_id);
    UPDATE ordens_servico SET status = 'concluida' WHERE id = p_os_id;
END //

CREATE PROCEDURE sp_cancelar_os(IN p_os_id INT UNSIGNED)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        CALL sp_validar_os_editavel(p_os_id);
        -- As triggers de os_pecas devolvem cada peça ao estoque
        DELETE FROM os_pecas WHERE os_id = p_os_id;
        UPDATE ordens_servico SET status = 'cancelada' WHERE id = p_os_id;
    COMMIT;
END //

CREATE PROCEDURE sp_entrada_estoque(IN p_peca_id INT UNSIGNED, IN p_quantidade INT)
BEGIN
    IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantidade de entrada deve ser positiva';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pecas WHERE id = p_peca_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Peca nao encontrada';
    END IF;

    CALL sp_registrar_movimentacao(p_peca_id, p_quantidade, NULL);
END //

-- Dias desde a última visita do cliente (NULL se nunca veio)
CREATE FUNCTION fn_dias_sem_visita(p_cliente_id INT UNSIGNED)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    RETURN (SELECT DATEDIFF(CURRENT_DATE, MAX(os.aberta_em))
              FROM ordens_servico os
              JOIN veiculos v ON v.id = os.veiculo_id
             WHERE v.cliente_id = p_cliente_id
               AND os.status <> 'cancelada');
END //

DELIMITER ;
