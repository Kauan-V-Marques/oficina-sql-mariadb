-- =============================================================
-- Oficina mecânica: estrutura do banco
-- MariaDB 11.8
-- =============================================================

DROP DATABASE IF EXISTS oficina;
CREATE DATABASE oficina CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE oficina;

CREATE TABLE clientes (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome        VARCHAR(120) NOT NULL,
    cpf         CHAR(11)     NOT NULL,
    telefone    VARCHAR(20),
    email       VARCHAR(120),
    criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_clientes_cpf UNIQUE (cpf),
    CONSTRAINT ck_clientes_cpf CHECK (cpf REGEXP '^[0-9]{11}$')
) ENGINE = InnoDB;

CREATE TABLE veiculos (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cliente_id  INT UNSIGNED      NOT NULL,
    placa       CHAR(7)           NOT NULL,
    marca       VARCHAR(40)       NOT NULL,
    modelo      VARCHAR(60)       NOT NULL,
    ano         SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT uq_veiculos_placa UNIQUE (placa),
    CONSTRAINT fk_veiculos_cliente FOREIGN KEY (cliente_id) REFERENCES clientes (id),
    -- Aceita o padrão antigo (ABC1234) e o Mercosul (ABC1D23)
    CONSTRAINT ck_veiculos_placa CHECK (placa REGEXP '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'),
    CONSTRAINT ck_veiculos_ano CHECK (ano BETWEEN 1950 AND 2100)
) ENGINE = InnoDB;

CREATE TABLE mecanicos (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome          VARCHAR(120) NOT NULL,
    especialidade VARCHAR(60)  NOT NULL,
    ativo         BOOLEAN      NOT NULL DEFAULT TRUE
) ENGINE = InnoDB;

-- Catálogo de serviços com preço de tabela
CREATE TABLE servicos (
    id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    descricao          VARCHAR(120)      NOT NULL,
    preco              DECIMAL(10, 2)    NOT NULL,
    tempo_estimado_min SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT uq_servicos_descricao UNIQUE (descricao),
    CONSTRAINT ck_servicos_preco CHECK (preco >= 0)
) ENGINE = InnoDB;

CREATE TABLE pecas (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    codigo         VARCHAR(20)    NOT NULL,
    descricao      VARCHAR(120)   NOT NULL,
    preco          DECIMAL(10, 2) NOT NULL,
    estoque        INT            NOT NULL DEFAULT 0,
    estoque_minimo INT            NOT NULL DEFAULT 0,
    CONSTRAINT uq_pecas_codigo UNIQUE (codigo),
    CONSTRAINT ck_pecas_preco CHECK (preco >= 0),
    CONSTRAINT ck_pecas_estoque CHECK (estoque >= 0),
    CONSTRAINT ck_pecas_estoque_minimo CHECK (estoque_minimo >= 0)
) ENGINE = InnoDB;

CREATE TABLE ordens_servico (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    veiculo_id     INT UNSIGNED   NOT NULL,
    mecanico_id    INT UNSIGNED   NOT NULL,
    status         ENUM ('aberta', 'em_andamento', 'concluida', 'cancelada') NOT NULL DEFAULT 'aberta',
    km_entrada     INT UNSIGNED   NOT NULL,
    observacoes    VARCHAR(500),
    aberta_em      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    concluida_em   DATETIME       NULL,
    -- Mantidos pelas triggers dos itens; o total é uma coluna calculada
    valor_servicos DECIMAL(10, 2) NOT NULL DEFAULT 0,
    valor_pecas    DECIMAL(10, 2) NOT NULL DEFAULT 0,
    valor_total    DECIMAL(10, 2) AS (valor_servicos + valor_pecas) STORED,
    CONSTRAINT fk_os_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculos (id),
    CONSTRAINT fk_os_mecanico FOREIGN KEY (mecanico_id) REFERENCES mecanicos (id),
    CONSTRAINT ck_os_datas CHECK (concluida_em IS NULL OR concluida_em >= aberta_em),
    INDEX idx_os_status (status),
    INDEX idx_os_concluida_em (concluida_em)
) ENGINE = InnoDB;

CREATE TABLE os_servicos (
    os_id          INT UNSIGNED      NOT NULL,
    servico_id     INT UNSIGNED      NOT NULL,
    quantidade     SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    preco_unitario DECIMAL(10, 2)    NOT NULL,
    PRIMARY KEY (os_id, servico_id),
    CONSTRAINT fk_os_servicos_os FOREIGN KEY (os_id) REFERENCES ordens_servico (id),
    CONSTRAINT fk_os_servicos_servico FOREIGN KEY (servico_id) REFERENCES servicos (id),
    CONSTRAINT ck_os_servicos_quantidade CHECK (quantidade > 0)
) ENGINE = InnoDB;

CREATE TABLE os_pecas (
    os_id          INT UNSIGNED      NOT NULL,
    peca_id        INT UNSIGNED      NOT NULL,
    quantidade     SMALLINT UNSIGNED NOT NULL,
    preco_unitario DECIMAL(10, 2)    NOT NULL,
    PRIMARY KEY (os_id, peca_id),
    CONSTRAINT fk_os_pecas_os FOREIGN KEY (os_id) REFERENCES ordens_servico (id),
    CONSTRAINT fk_os_pecas_peca FOREIGN KEY (peca_id) REFERENCES pecas (id),
    CONSTRAINT ck_os_pecas_quantidade CHECK (quantidade > 0)
) ENGINE = InnoDB;

-- Histórico de toda entrada e saída de peças (alimentado pelas triggers)
CREATE TABLE movimentacoes_estoque (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    peca_id    INT UNSIGNED NOT NULL,
    tipo       ENUM ('entrada', 'saida') NOT NULL,
    quantidade INT          NOT NULL,
    os_id      INT UNSIGNED NULL,
    criado_em  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mov_peca FOREIGN KEY (peca_id) REFERENCES pecas (id),
    CONSTRAINT fk_mov_os FOREIGN KEY (os_id) REFERENCES ordens_servico (id),
    CONSTRAINT ck_mov_quantidade CHECK (quantidade > 0),
    INDEX idx_mov_peca_data (peca_id, criado_em)
) ENGINE = InnoDB;
