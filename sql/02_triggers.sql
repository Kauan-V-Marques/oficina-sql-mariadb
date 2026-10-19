-- =============================================================
-- Regras de negócio garantidas pelo próprio banco
--   * itens só mudam enquanto a OS está aberta ou em andamento
--   * peça usada na OS sai do estoque (e volta se for removida)
--   * toda movimentação de estoque fica registrada
--   * valores da OS são recalculados a cada alteração de item
--   * OS concluída precisa ter pelo menos um serviço
--   * OS não é excluída, só cancelada
-- =============================================================

USE oficina;

DELIMITER //

CREATE PROCEDURE sp_validar_os_editavel(IN p_os_id INT UNSIGNED)
BEGIN
    DECLARE v_status VARCHAR(20);

    SELECT status INTO v_status FROM ordens_servico WHERE id = p_os_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de servico nao encontrada';
    ELSEIF v_status NOT IN ('aberta', 'em_andamento') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de servico concluida ou cancelada nao pode ser alterada';
    END IF;
END //

CREATE PROCEDURE sp_recalcular_os(IN p_os_id INT UNSIGNED)
BEGIN
    UPDATE ordens_servico
       SET valor_servicos = (SELECT COALESCE(SUM(quantidade * preco_unitario), 0)
                               FROM os_servicos WHERE os_id = p_os_id),
           valor_pecas    = (SELECT COALESCE(SUM(quantidade * preco_unitario), 0)
                               FROM os_pecas WHERE os_id = p_os_id)
     WHERE id = p_os_id;
END //

CREATE PROCEDURE sp_registrar_movimentacao(
    IN p_peca_id INT UNSIGNED,
    IN p_delta INT,
    IN p_os_id INT UNSIGNED)
BEGIN
    -- delta negativo = saída do estoque, positivo = entrada
    IF p_delta <> 0 THEN
        UPDATE pecas SET estoque = estoque + p_delta WHERE id = p_peca_id;
        INSERT INTO movimentacoes_estoque (peca_id, tipo, quantidade, os_id)
        VALUES (p_peca_id, IF(p_delta > 0, 'entrada', 'saida'), ABS(p_delta), p_os_id);
    END IF;
END //

-- ---------- Peças da OS ----------

CREATE TRIGGER trg_os_pecas_bi BEFORE INSERT ON os_pecas
FOR EACH ROW
BEGIN
    DECLARE v_estoque INT;

    CALL sp_validar_os_editavel(NEW.os_id);

    SELECT estoque INTO v_estoque FROM pecas WHERE id = NEW.peca_id;
    IF v_estoque < NEW.quantidade THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estoque insuficiente para a peca';
    END IF;
END //

CREATE TRIGGER trg_os_pecas_ai AFTER INSERT ON os_pecas
FOR EACH ROW
BEGIN
    CALL sp_registrar_movimentacao(NEW.peca_id, -CAST(NEW.quantidade AS SIGNED), NEW.os_id);
    CALL sp_recalcular_os(NEW.os_id);
END //

CREATE TRIGGER trg_os_pecas_bu BEFORE UPDATE ON os_pecas
FOR EACH ROW
BEGIN
    DECLARE v_estoque INT;

    IF NEW.os_id <> OLD.os_id OR NEW.peca_id <> OLD.peca_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Remova o item e adicione novamente para trocar a peca';
    END IF;

    CALL sp_validar_os_editavel(NEW.os_id);

    IF NEW.quantidade > OLD.quantidade THEN
        SELECT estoque INTO v_estoque FROM pecas WHERE id = NEW.peca_id;
        IF v_estoque < NEW.quantidade - OLD.quantidade THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estoque insuficiente para a peca';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_os_pecas_au AFTER UPDATE ON os_pecas
FOR EACH ROW
BEGIN
    -- Colunas UNSIGNED: converter antes de subtrair para o resultado poder ser negativo
    CALL sp_registrar_movimentacao(NEW.peca_id,
        CAST(OLD.quantidade AS SIGNED) - CAST(NEW.quantidade AS SIGNED), NEW.os_id);
    CALL sp_recalcular_os(NEW.os_id);
END //

CREATE TRIGGER trg_os_pecas_bd BEFORE DELETE ON os_pecas
FOR EACH ROW
BEGIN
    CALL sp_validar_os_editavel(OLD.os_id);
END //

CREATE TRIGGER trg_os_pecas_ad AFTER DELETE ON os_pecas
FOR EACH ROW
BEGIN
    CALL sp_registrar_movimentacao(OLD.peca_id, OLD.quantidade, OLD.os_id);
    CALL sp_recalcular_os(OLD.os_id);
END //

-- ---------- Serviços da OS ----------

CREATE TRIGGER trg_os_servicos_bi BEFORE INSERT ON os_servicos
FOR EACH ROW
BEGIN
    CALL sp_validar_os_editavel(NEW.os_id);
END //

CREATE TRIGGER trg_os_servicos_ai AFTER INSERT ON os_servicos
FOR EACH ROW
BEGIN
    CALL sp_recalcular_os(NEW.os_id);
END //

CREATE TRIGGER trg_os_servicos_bu BEFORE UPDATE ON os_servicos
FOR EACH ROW
BEGIN
    IF NEW.os_id <> OLD.os_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nao e possivel mover o servico para outra OS';
    END IF;
    CALL sp_validar_os_editavel(NEW.os_id);
END //

CREATE TRIGGER trg_os_servicos_au AFTER UPDATE ON os_servicos
FOR EACH ROW
BEGIN
    CALL sp_recalcular_os(NEW.os_id);
END //

CREATE TRIGGER trg_os_servicos_bd BEFORE DELETE ON os_servicos
FOR EACH ROW
BEGIN
    CALL sp_validar_os_editavel(OLD.os_id);
END //

CREATE TRIGGER trg_os_servicos_ad AFTER DELETE ON os_servicos
FOR EACH ROW
BEGIN
    CALL sp_recalcular_os(OLD.os_id);
END //

-- ---------- Ordem de serviço ----------

CREATE TRIGGER trg_os_bu BEFORE UPDATE ON ordens_servico
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF OLD.status IN ('concluida', 'cancelada') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de servico concluida ou cancelada nao pode mudar de status';
        END IF;

        IF NEW.status = 'concluida' THEN
            IF NOT EXISTS (SELECT 1 FROM os_servicos WHERE os_id = NEW.id) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de servico sem servicos nao pode ser concluida';
            END IF;
            IF NEW.concluida_em IS NULL THEN
                SET NEW.concluida_em = NOW();
            END IF;
        END IF;
    END IF;
END //

CREATE TRIGGER trg_os_bd BEFORE DELETE ON ordens_servico
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordens de servico nao sao excluidas; use sp_cancelar_os';
END //

DELIMITER ;
