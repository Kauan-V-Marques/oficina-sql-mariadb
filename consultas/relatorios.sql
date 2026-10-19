-- =============================================================
-- Relatórios gerenciais (CTEs e funções de janela)
-- =============================================================

USE oficina;

-- 1) Ranking de clientes por valor gasto, com participação no faturamento
WITH gasto_por_cliente AS (
    SELECT c.id, c.nome, SUM(os.valor_total) AS total
      FROM clientes c
      JOIN veiculos v        ON v.cliente_id = c.id
      JOIN ordens_servico os ON os.veiculo_id = v.id AND os.status = 'concluida'
     GROUP BY c.id, c.nome
)
SELECT RANK() OVER (ORDER BY total DESC)                    AS posicao,
       nome,
       total,
       ROUND(100 * total / SUM(total) OVER (), 1)          AS percentual
  FROM gasto_por_cliente
 ORDER BY posicao
 LIMIT 5;

-- 2) Faturamento mensal com acumulado no ano e variação sobre o mês anterior
SELECT mes,
       faturamento,
       SUM(faturamento) OVER (ORDER BY mes)                            AS acumulado,
       ROUND(100 * (faturamento - LAG(faturamento) OVER (ORDER BY mes))
                 / LAG(faturamento) OVER (ORDER BY mes), 1)             AS variacao_pct
  FROM vw_faturamento_mensal
 ORDER BY mes;

-- 3) Serviços mais vendidos e quanto cada um representa da receita de mão de obra
SELECT s.descricao,
       SUM(oss.quantidade)                                              AS vezes,
       SUM(oss.quantidade * oss.preco_unitario)                         AS receita,
       ROUND(100 * SUM(oss.quantidade * oss.preco_unitario)
                 / SUM(SUM(oss.quantidade * oss.preco_unitario)) OVER (), 1) AS percentual
  FROM os_servicos oss
  JOIN servicos s        ON s.id = oss.servico_id
  JOIN ordens_servico os ON os.id = oss.os_id AND os.status = 'concluida'
 GROUP BY s.id, s.descricao
 ORDER BY receita DESC;

-- 4) Giro de peças: saídas no período e quantos dias o estoque dura no ritmo médio
WITH periodo AS (
    SELECT DATEDIFF(MAX(criado_em), MIN(criado_em)) + 1 AS dias
      FROM movimentacoes_estoque
     WHERE tipo = 'saida'
),
saidas AS (
    SELECT peca_id, SUM(quantidade) AS total_saida
      FROM movimentacoes_estoque
     WHERE tipo = 'saida'
     GROUP BY peca_id
)
SELECT p.codigo,
       p.descricao,
       s.total_saida,
       ROUND(30 * s.total_saida / per.dias, 1)            AS media_mensal,
       p.estoque,
       ROUND(p.estoque / (s.total_saida / per.dias))      AS dias_de_estoque
  FROM saidas s
  JOIN pecas p ON p.id = s.peca_id
 CROSS JOIN periodo per
 ORDER BY dias_de_estoque;

-- 5) Clientes que não aparecem há mais de 60 dias (para campanha de revisão)
SELECT c.nome,
       c.telefone,
       fn_dias_sem_visita(c.id) AS dias_sem_visita
  FROM clientes c
 WHERE COALESCE(fn_dias_sem_visita(c.id), 9999) > 60
 ORDER BY dias_sem_visita IS NULL, dias_sem_visita DESC;

-- 6) Intervalo médio (km) entre trocas de óleo por veículo
WITH trocas AS (
    SELECT os.veiculo_id,
           os.km_entrada,
           os.km_entrada - LAG(os.km_entrada) OVER (PARTITION BY os.veiculo_id
                                                    ORDER BY os.aberta_em) AS km_desde_ultima
      FROM ordens_servico os
      JOIN os_servicos oss ON oss.os_id = os.id
     WHERE oss.servico_id = (SELECT id FROM servicos WHERE descricao = 'Troca de oleo e filtro')
       AND os.status = 'concluida'
)
SELECT v.placa,
       CONCAT(v.marca, ' ', v.modelo) AS veiculo,
       COUNT(*)                       AS trocas,
       ROUND(AVG(t.km_desde_ultima))  AS km_medio_entre_trocas
  FROM trocas t
  JOIN veiculos v ON v.id = t.veiculo_id
 GROUP BY v.id, v.placa, v.marca, v.modelo
HAVING COUNT(*) > 1;
