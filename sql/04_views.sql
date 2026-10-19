-- =============================================================
-- Visões prontas para o balcão e para a gestão
-- =============================================================

USE oficina;

-- OS com cliente, veículo e mecânico em uma linha só
CREATE OR REPLACE VIEW vw_ordens_detalhadas AS
SELECT os.id                                   AS os_id,
       os.status,
       os.aberta_em,
       os.concluida_em,
       c.nome                                  AS cliente,
       v.placa,
       CONCAT(v.marca, ' ', v.modelo, ' ', v.ano) AS veiculo,
       m.nome                                  AS mecanico,
       os.km_entrada,
       os.valor_servicos,
       os.valor_pecas,
       os.valor_total
  FROM ordens_servico os
  JOIN veiculos  v ON v.id = os.veiculo_id
  JOIN clientes  c ON c.id = v.cliente_id
  JOIN mecanicos m ON m.id = os.mecanico_id;

-- Peças no estoque mínimo ou abaixo, com sugestão de compra
CREATE OR REPLACE VIEW vw_pecas_para_repor AS
SELECT p.codigo,
       p.descricao,
       p.estoque,
       p.estoque_minimo,
       (p.estoque_minimo * 2) - p.estoque AS sugestao_compra
  FROM pecas p
 WHERE p.estoque <= p.estoque_minimo;

-- Faturamento por mês (somente OS concluídas)
CREATE OR REPLACE VIEW vw_faturamento_mensal AS
SELECT DATE_FORMAT(os.concluida_em, '%Y-%m') AS mes,
       COUNT(*)                              AS ordens_concluidas,
       SUM(os.valor_servicos)                AS servicos,
       SUM(os.valor_pecas)                   AS pecas,
       SUM(os.valor_total)                   AS faturamento,
       ROUND(AVG(os.valor_total), 2)         AS ticket_medio
  FROM ordens_servico os
 WHERE os.status = 'concluida'
 GROUP BY DATE_FORMAT(os.concluida_em, '%Y-%m');

-- Produtividade de cada mecânico
CREATE OR REPLACE VIEW vw_desempenho_mecanicos AS
SELECT m.id                                                         AS mecanico_id,
       m.nome,
       m.especialidade,
       COUNT(os.id)                                                 AS ordens_concluidas,
       COALESCE(SUM(os.valor_total), 0)                             AS faturamento,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, os.aberta_em, os.concluida_em)) / 60, 1) AS horas_medias_por_os
  FROM mecanicos m
  LEFT JOIN ordens_servico os ON os.mecanico_id = m.id AND os.status = 'concluida'
 GROUP BY m.id, m.nome, m.especialidade;

-- Histórico de cada veículo
CREATE OR REPLACE VIEW vw_historico_veiculos AS
SELECT v.placa,
       CONCAT(v.marca, ' ', v.modelo)  AS veiculo,
       c.nome                          AS cliente,
       COUNT(os.id)                    AS visitas,
       MAX(os.km_entrada)              AS ultima_km,
       MAX(os.aberta_em)               AS ultima_visita,
       COALESCE(SUM(os.valor_total), 0) AS total_gasto
  FROM veiculos v
  JOIN clientes c ON c.id = v.cliente_id
  LEFT JOIN ordens_servico os ON os.veiculo_id = v.id AND os.status = 'concluida'
 GROUP BY v.id, v.placa, v.marca, v.modelo, c.nome;
