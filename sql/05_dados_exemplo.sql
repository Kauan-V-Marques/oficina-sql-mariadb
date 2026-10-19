-- =============================================================
-- Dados de exemplo (fictícios) para testar consultas e relatórios
-- =============================================================

USE oficina;

INSERT INTO clientes (nome, cpf, telefone, email) VALUES
    ('Ana Beatriz Souza', '10000000001', '(15) 90000-0001', 'ana.souza@example.com'),
    ('Bruno Carvalho',    '10000000002', '(15) 90000-0002', 'bruno.carvalho@example.com'),
    ('Camila Ferreira',   '10000000003', '(15) 90000-0003', 'camila.ferreira@example.com'),
    ('Diego Martins',     '10000000004', '(15) 90000-0004', 'diego.martins@example.com'),
    ('Eduarda Lima',      '10000000005', '(15) 90000-0005', 'eduarda.lima@example.com'),
    ('Felipe Andrade',    '10000000006', '(15) 90000-0006', 'felipe.andrade@example.com'),
    ('Gabriela Nunes',    '10000000007', '(15) 90000-0007', 'gabriela.nunes@example.com'),
    ('Henrique Barros',   '10000000008', '(15) 90000-0008', 'henrique.barros@example.com'),
    ('Isabela Cardoso',   '10000000009', '(15) 90000-0009', 'isabela.cardoso@example.com');

INSERT INTO veiculos (cliente_id, placa, marca, modelo, ano) VALUES
    (1, 'FRT2A31', 'Volkswagen', 'Gol',      2018),
    (2, 'GHM4B52', 'Fiat',       'Argo',     2021),
    (3, 'KLP7C18', 'Chevrolet',  'Onix',     2020),
    (4, 'BQX3D44', 'Toyota',     'Corolla',  2019),
    (5, 'EZN8E67', 'Honda',      'Fit',      2016),
    (6, 'HTR1F90', 'Hyundai',    'HB20',     2022),
    (7, 'JWS5G12', 'Renault',    'Kwid',     2023),
    (8, 'DMC6H75', 'Ford',       'Ka',       2017),
    (2, 'PLU9J03', 'Fiat',       'Strada',   2024),
    (5, 'RVA0K48', 'Jeep',       'Renegade', 2019),
    (9, 'MNB2L56', 'Nissan',     'Kicks',    2021);

INSERT INTO mecanicos (nome, especialidade, ativo) VALUES
    ('Carlos Mendes',  'Motor',               TRUE),
    ('Fernanda Rocha', 'Freios e suspensao',  TRUE),
    ('Rafael Teixeira','Eletrica',            TRUE),
    ('Juliana Prado',  'Revisao geral',       TRUE),
    ('Marcos Vieira',  'Motor',               FALSE);

INSERT INTO servicos (descricao, preco, tempo_estimado_min) VALUES
    ('Troca de oleo e filtro',            90.00,  40),
    ('Alinhamento e balanceamento',      120.00,  60),
    ('Revisao de freios',                150.00,  90),
    ('Troca de pastilhas de freio',      110.00,  60),
    ('Troca de correia dentada',         380.00, 180),
    ('Diagnostico eletronico (scanner)', 140.00,  45),
    ('Troca de velas',                    80.00,  40),
    ('Troca de amortecedores (par)',     260.00, 150),
    ('Limpeza de bicos injetores',       180.00,  90),
    ('Troca de bateria',                  40.00,  20);

INSERT INTO pecas (codigo, descricao, preco, estoque, estoque_minimo) VALUES
    ('FLT-OL-01',   'Filtro de oleo',                      38.90, 30, 10),
    ('OL-5W30-1L',  'Oleo 5W30 sintetico (1 L)',           54.90, 80, 30),
    ('FLT-AR-01',   'Filtro de ar',                        49.90, 20,  8),
    ('FLT-CB-01',   'Filtro de combustivel',               42.50, 15,  6),
    ('PST-DIA-01',  'Pastilha de freio dianteira (jogo)', 189.90, 12,  4),
    ('DSC-DIA-01',  'Disco de freio dianteiro',           239.90,  8,  4),
    ('VLA-IGN-01',  'Vela de ignicao',                     32.90, 40, 16),
    ('COR-DENT-01', 'Correia dentada',                    159.90,  6,  4),
    ('BAT-60AH',    'Bateria 60 Ah',                      489.90,  5,  2),
    ('AMT-DIA-01',  'Amortecedor dianteiro',              329.90,  6,  4),
    ('LMP-H4',      'Lampada H4',                          24.90, 25, 10),
    ('FLD-FRE-500', 'Fluido de freio DOT 4 (500 ml)',      36.90, 18,  6),
    ('ADT-RAD-1L',  'Aditivo de radiador (1 L)',           29.90, 20,  8),
    ('PNE-175-70',  'Pneu 175/70 R14',                    399.90, 12,  8),
    ('PAL-LIMP-01', 'Palheta do limpador (par)',           59.90, 10,  4);

-- -------------------------------------------------------------
-- Ordens de serviço de jan a out/2026. As datas são definidas na
-- mão para montar um histórico; no dia a dia usa-se sp_abrir_os.
-- -------------------------------------------------------------

DELIMITER //

CREATE PROCEDURE sp_exemplo_os(
    IN p_veiculo_id   INT UNSIGNED,
    IN p_mecanico_id  INT UNSIGNED,
    IN p_km           INT UNSIGNED,
    IN p_aberta_em    DATETIME,
    IN p_servicos     VARCHAR(100),  -- 'id:qtd,id:qtd'
    IN p_pecas        VARCHAR(100),
    IN p_concluida_em DATETIME)      -- NULL = continua em andamento
BEGIN
    DECLARE v_os INT UNSIGNED;
    DECLARE v_item VARCHAR(20);
    DECLARE v_lista VARCHAR(100);

    INSERT INTO ordens_servico (veiculo_id, mecanico_id, km_entrada, aberta_em)
    VALUES (p_veiculo_id, p_mecanico_id, p_km, p_aberta_em);
    SET v_os = LAST_INSERT_ID();

    SET v_lista = p_servicos;
    WHILE v_lista IS NOT NULL AND v_lista <> '' DO
        SET v_item = SUBSTRING_INDEX(v_lista, ',', 1);
        CALL sp_adicionar_servico(v_os, SUBSTRING_INDEX(v_item, ':', 1), SUBSTRING_INDEX(v_item, ':', -1));
        SET v_lista = IF(LOCATE(',', v_lista) > 0, SUBSTRING(v_lista, LOCATE(',', v_lista) + 1), '');
    END WHILE;

    SET v_lista = p_pecas;
    WHILE v_lista IS NOT NULL AND v_lista <> '' DO
        SET v_item = SUBSTRING_INDEX(v_lista, ',', 1);
        CALL sp_adicionar_peca(v_os, SUBSTRING_INDEX(v_item, ':', 1), SUBSTRING_INDEX(v_item, ':', -1));
        SET v_lista = IF(LOCATE(',', v_lista) > 0, SUBSTRING(v_lista, LOCATE(',', v_lista) + 1), '');
    END WHILE;

    IF p_concluida_em IS NOT NULL THEN
        UPDATE ordens_servico SET status = 'concluida', concluida_em = p_concluida_em WHERE id = v_os;
    END IF;
END //

DELIMITER ;

CALL sp_exemplo_os( 1, 4,  61200, '2026-01-06 08:30', '1:1',     '1:1,2:4',          '2026-01-06 10:40');
CALL sp_exemplo_os( 3, 2,  38900, '2026-01-14 09:00', '3:1,4:1', '5:1,12:1',         '2026-01-14 16:20');
CALL sp_exemplo_os( 4, 1,  72400, '2026-01-22 13:00', '5:1',     '8:1',              '2026-01-23 11:00');
CALL sp_exemplo_os( 2, 4,  21500, '2026-02-03 08:15', '1:1,2:1', '1:1,2:4',          '2026-02-03 12:15');
CALL sp_exemplo_os( 5, 3,  98300, '2026-02-11 10:00', '6:1,10:1','9:1',              '2026-02-11 15:00');
CALL sp_exemplo_os( 6, 4,  15800, '2026-02-25 08:40', '1:1',     '1:1,2:4,3:1',      '2026-02-25 11:30');
CALL sp_exemplo_os( 8, 2,  84100, '2026-03-05 14:00', '8:1',     '10:2',             '2026-03-06 10:00');
CALL sp_exemplo_os( 7, 3,   9800, '2026-03-17 11:00', '6:1',     '11:2',             '2026-03-17 14:10');
CALL sp_exemplo_os(10, 1,  55600, '2026-03-26 15:00', '7:1,9:1', '7:4,4:1',          '2026-03-27 09:30');
CALL sp_exemplo_os( 1, 2,  66900, '2026-04-07 09:30', '3:1,4:1', '5:1,6:2,12:1',     '2026-04-07 17:45');
CALL sp_exemplo_os( 9, 4,   8200, '2026-04-20 08:00', '1:1,2:1', '1:1,2:4,14:2',     '2026-04-20 13:00');
CALL sp_exemplo_os( 3, 4,  45100, '2026-05-04 08:10', '1:1',     '1:1,2:4,13:1',     '2026-05-04 10:20');
CALL sp_exemplo_os( 4, 2,  78800, '2026-05-19 10:30', '2:1,8:1', '10:2,14:4',        '2026-05-20 16:00');
CALL sp_exemplo_os( 2, 3,  27600, '2026-06-02 08:30', '6:1,10:1','9:1',              '2026-06-02 11:10');
CALL sp_exemplo_os( 5, 1, 103200, '2026-06-16 09:00', '5:1,7:1', '8:1,7:4',          '2026-06-17 15:30');
CALL sp_exemplo_os( 6, 4,  22300, '2026-07-01 08:20', '1:1,2:1', '1:1,2:4,15:1',     '2026-07-01 12:40');
CALL sp_exemplo_os( 8, 2,  90500, '2026-07-21 10:00', '3:1,4:1', '5:1,12:1',         '2026-07-21 15:50');
CALL sp_exemplo_os(10, 4,  63100, '2026-08-05 08:00', '1:1',     '1:1,2:5,3:1',      '2026-08-05 10:30');
CALL sp_exemplo_os( 1, 1,  72400, '2026-08-19 10:00', '9:1',     '4:1',              '2026-08-19 14:00');
CALL sp_exemplo_os( 9, 2,  15900, '2026-09-02 08:30', '2:1',     '14:2',             '2026-09-02 11:20');
CALL sp_exemplo_os( 7, 4,  16400, '2026-09-15 08:00', '1:1',     '1:1,2:4',          '2026-09-15 10:10');

-- Uma OS cancelada (a peça volta para o estoque) e duas em aberto
CALL sp_exemplo_os( 4, 3,  81200, '2026-09-23 09:00', '6:1',     '11:1',             NULL);
SET @os_cancelada = (SELECT MAX(id) FROM ordens_servico);
CALL sp_cancelar_os(@os_cancelada);
CALL sp_exemplo_os( 3, 2,  49800, '2026-10-05 08:30', '3:1',     '5:1',              NULL);
CALL sp_exemplo_os( 5, 1, 108000, '2026-10-08 13:00', '',        '',                 NULL);

-- Reposição de estoque
CALL sp_entrada_estoque(1, 10);

-- As movimentações foram gravadas agora; alinha as datas com as das OS
UPDATE movimentacoes_estoque m
  JOIN ordens_servico os ON os.id = m.os_id
   SET m.criado_em = COALESCE(os.concluida_em, os.aberta_em);

DROP PROCEDURE sp_exemplo_os;
