-- =============================================================
-- Testes automatizados das regras de negócio
-- Rodar depois de criar o banco: qualquer falha interrompe o script
-- =============================================================

USE oficina;

DELIMITER //

CREATE PROCEDURE assert_igual(IN p_descricao VARCHAR(200), IN p_esperado VARCHAR(100), IN p_obtido VARCHAR(100))
BEGIN
    DECLARE v_msg VARCHAR(512);
    IF NOT (p_esperado <=> p_obtido) THEN
        SET v_msg = CONCAT('FALHOU: ', p_descricao, ' (esperado ', COALESCE(p_esperado, 'NULL'),
                           ', obtido ', COALESCE(p_obtido, 'NULL'), ')');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    SELECT CONCAT('ok  ', p_descricao) AS resultado;
END //

-- Executa um comando que DEVE falhar com uma mensagem contendo p_trecho
CREATE PROCEDURE assert_erro(IN p_descricao VARCHAR(200), IN p_sql TEXT, IN p_trecho VARCHAR(200))
BEGIN
    DECLARE v_erro VARCHAR(512) DEFAULT NULL;
    DECLARE v_msg VARCHAR(512);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_erro = MESSAGE_TEXT;

    EXECUTE IMMEDIATE p_sql;

    IF v_erro IS NULL THEN
        SET v_msg = CONCAT('FALHOU: ', p_descricao, ' (o comando deveria ter falhado)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF LOCATE(p_trecho, v_erro) = 0 THEN
        SET v_msg = CONCAT('FALHOU: ', p_descricao, ' (erro inesperado: ', v_erro, ')');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
    SELECT CONCAT('ok  ', p_descricao) AS resultado;
END //

DELIMITER ;

-- ---------- Preparação ----------
INSERT INTO clientes (nome, cpf) VALUES ('Cliente de Teste', '99999999999');
SET @cliente = LAST_INSERT_ID();
INSERT INTO veiculos (cliente_id, placa, marca, modelo, ano) VALUES (@cliente, 'TST1A23', 'Teste', 'Modelo', 2020);
INSERT INTO pecas (codigo, descricao, preco, estoque, estoque_minimo) VALUES ('TESTE-01', 'Peca de teste', 100.00, 5, 1);
SET @peca = LAST_INSERT_ID();
SET @troca_oleo = (SELECT id FROM servicos WHERE descricao = 'Troca de oleo e filtro');

-- ---------- Abertura de OS ----------
CALL sp_abrir_os('tst-1a23', 1, 1000, 'teste automatizado', @os);
CALL assert_igual('abre OS com placa em minusculas e com hifen', 'aberta',
                  (SELECT status FROM ordens_servico WHERE id = @os));

CALL assert_erro('nao abre segunda OS para o mesmo veiculo',
                 'CALL sp_abrir_os(''TST1A23'', 1, 1500, NULL, @x)', 'ja possui ordem');
CALL assert_erro('nao abre OS com mecanico inativo',
                 'CALL sp_abrir_os(''TST1A23'', 5, 1500, NULL, @x)', 'inativo');
CALL assert_erro('nao abre OS para placa inexistente',
                 'CALL sp_abrir_os(''ZZZ9Z99'', 1, 1500, NULL, @x)', 'nao cadastrado');

-- ---------- Peças e estoque ----------
CALL sp_adicionar_peca(@os, @peca, 2);
CALL assert_igual('peca usada sai do estoque', '3', (SELECT estoque FROM pecas WHERE id = @peca));
CALL assert_igual('primeiro item coloca a OS em andamento', 'em_andamento',
                  (SELECT status FROM ordens_servico WHERE id = @os));
CALL assert_igual('valor das pecas e calculado', '200.00',
                  (SELECT valor_pecas FROM ordens_servico WHERE id = @os));
CALL assert_igual('saida fica registrada no historico', '2',
                  (SELECT quantidade FROM movimentacoes_estoque
                    WHERE peca_id = @peca AND os_id = @os AND tipo = 'saida'));

CALL sp_adicionar_peca(@os, @peca, 1);
CALL assert_igual('adicionar a mesma peca soma a quantidade', '3',
                  (SELECT quantidade FROM os_pecas WHERE os_id = @os AND peca_id = @peca));
CALL assert_igual('estoque acompanha a soma', '2', (SELECT estoque FROM pecas WHERE id = @peca));

CALL assert_erro('bloqueia peca sem estoque suficiente',
                 'CALL sp_adicionar_peca(@os, @peca, 10)', 'Estoque insuficiente');
CALL assert_igual('estoque nao muda quando a peca e recusada', '2',
                  (SELECT estoque FROM pecas WHERE id = @peca));

CALL sp_remover_peca(@os, @peca);
CALL assert_igual('remover a peca devolve ao estoque', '5', (SELECT estoque FROM pecas WHERE id = @peca));
CALL assert_igual('valor das pecas volta a zero', '0.00',
                  (SELECT valor_pecas FROM ordens_servico WHERE id = @os));

-- ---------- Conclusão ----------
CALL assert_erro('nao conclui OS sem servicos', 'CALL sp_concluir_os(@os)', 'sem servicos');

CALL sp_adicionar_servico(@os, @troca_oleo, 1);
CALL sp_adicionar_peca(@os, @peca, 1);
CALL assert_igual('total = servicos + pecas', '190.00',
                  (SELECT valor_total FROM ordens_servico WHERE id = @os));

CALL sp_concluir_os(@os);
CALL assert_igual('OS concluida', 'concluida', (SELECT status FROM ordens_servico WHERE id = @os));
CALL assert_igual('data de conclusao preenchida automaticamente', '1',
                  (SELECT concluida_em IS NOT NULL FROM ordens_servico WHERE id = @os));

CALL assert_erro('OS concluida nao aceita novos itens',
                 'CALL sp_adicionar_peca(@os, @peca, 1)', 'nao pode ser alterada');
CALL assert_erro('OS concluida nao volta a ficar aberta',
                 'UPDATE ordens_servico SET status = ''aberta'' WHERE id = @os', 'nao pode mudar de status');
CALL assert_erro('OS nao pode ser excluida',
                 'DELETE FROM ordens_servico WHERE id = @os', 'nao sao excluidas');
CALL assert_erro('quilometragem nao pode ser menor que a da ultima visita',
                 'CALL sp_abrir_os(''TST1A23'', 1, 900, NULL, @x)', 'Quilometragem menor');

-- ---------- Cancelamento ----------
CALL sp_abrir_os('TST1A23', 2, 2000, NULL, @os2);
CALL sp_adicionar_peca(@os2, @peca, 2);
CALL assert_igual('estoque antes do cancelamento', '2', (SELECT estoque FROM pecas WHERE id = @peca));
CALL sp_cancelar_os(@os2);
CALL assert_igual('cancelar devolve as pecas ao estoque', '4', (SELECT estoque FROM pecas WHERE id = @peca));
CALL assert_igual('OS fica cancelada', 'cancelada', (SELECT status FROM ordens_servico WHERE id = @os2));

-- ---------- Restrições de dados ----------
CALL assert_erro('placa em formato invalido e recusada',
                 'INSERT INTO veiculos (cliente_id, placa, marca, modelo, ano) VALUES (@cliente, ''AB12345'', ''X'', ''Y'', 2020)',
                 'ck_veiculos_placa');
CALL assert_erro('CPF com letras e recusado',
                 'INSERT INTO clientes (nome, cpf) VALUES (''X'', ''1234567890A'')', 'ck_clientes_cpf');
CALL assert_erro('entrada de estoque precisa ser positiva',
                 'CALL sp_entrada_estoque(@peca, 0)', 'deve ser positiva');

-- ---------- Views ----------
CALL assert_igual('view detalhada mostra a OS do teste', 'Cliente de Teste',
                  (SELECT cliente FROM vw_ordens_detalhadas WHERE os_id = @os));
CALL assert_igual('peca de teste nao precisa de reposicao', '0',
                  (SELECT COUNT(*) FROM vw_pecas_para_repor WHERE codigo = 'TESTE-01'));

DROP PROCEDURE assert_igual;
DROP PROCEDURE assert_erro;

SELECT 'Todos os testes passaram' AS resultado;
