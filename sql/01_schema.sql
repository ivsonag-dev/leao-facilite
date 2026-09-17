-- ============================================================================
-- LEÃO FACILITE — Etapa 1: estrutura de dados
-- Executar UMA VEZ no SQL Editor do Supabase (projeto novo e vazio).
-- Ordem: este arquivo primeiro, depois 02_seguranca.sql.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Fuso e data de referência
-- Toda virada diária (renovação de Lions, fim de cota) usa o horário de Recife.
-- ---------------------------------------------------------------------------
create or replace function public.hoje()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/Recife')::date;
$$;

-- ---------------------------------------------------------------------------
-- parametros — valores de regra que mudam sem precisar alterar código
-- ---------------------------------------------------------------------------
create table public.parametros (
  chave          text primary key,
  valor          jsonb not null,
  descricao      text,
  atualizado_em  timestamptz not null default now()
);

insert into public.parametros (chave, valor, descricao) values
  ('lions_dia_gratuito', '300',    'Lions diários de quem não tem cota ativa'),
  ('custo_junior',       '20',     'Custo padrão de uma partida Júnior'),
  ('custo_pleno',        '30',     'Custo padrão de uma partida Pleno'),
  ('custo_senior',       '60',     'Custo padrão de uma partida Sênior'),
  ('alerta_fim_cota',    '5',      'Dias restantes que disparam o alerta de fim de cota'),
  ('cadastro_aberto',    'true',   'Permite novos cadastros na plataforma');

create or replace function public.parametro_int(p_chave text)
returns int
language sql
stable
as $$
  select (valor #>> '{}')::int from public.parametros where chave = p_chave;
$$;

-- ---------------------------------------------------------------------------
-- planos — a cota vendida. Hoje só o mensal está ativo.
-- Para abrir um plano novo no futuro: update planos set ativo = true.
-- ---------------------------------------------------------------------------
create table public.planos (
  id               smallserial primary key,
  slug             text unique not null,
  nome             text not null,
  descricao        text,
  preco_centavos   int not null,
  dias             int not null,
  lions_dia        int not null,
  ativo            boolean not null default false,
  ordem            smallint not null default 0,
  cakto_produto_id text,
  criado_em        timestamptz not null default now()
);

insert into public.planos (slug, nome, descricao, preco_centavos, dias, lions_dia, ativo, ordem) values
  ('mensal',     'Cota mensal',     '30 dias com 900 Lions por dia',  1000, 30,  900, true,  1),
  ('trimestral', 'Cota trimestral', '90 dias com 900 Lions por dia',  2700, 90,  900, false, 2),
  ('semestral',  'Cota semestral',  '180 dias com 900 Lions por dia', 5100, 180, 900, false, 3);
-- Os preços de trimestral e semestral são provisórios: defina antes de ativar.

-- ---------------------------------------------------------------------------
-- temporadas — o ranking zera a cada mês; o histórico fica guardado
-- ---------------------------------------------------------------------------
create table public.temporadas (
  id        smallserial primary key,
  nome      text not null,
  inicio    date not null,
  fim       date not null,
  encerrada boolean not null default false,
  check (fim >= inicio)
);

insert into public.temporadas (nome, inicio, fim)
select
  to_char(date_trunc('month', public.hoje()), 'TMMonth/YYYY'),
  date_trunc('month', public.hoje())::date,
  (date_trunc('month', public.hoje()) + interval '1 month - 1 day')::date;

create or replace function public.temporada_atual()
returns smallint
language sql
stable
as $$
  select id from public.temporadas
  where public.hoje() between inicio and fim
  order by inicio desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- perfis — uma linha por usuário, espelhando auth.users
-- ---------------------------------------------------------------------------
create table public.perfis (
  id                uuid primary key references auth.users(id) on delete cascade,
  instagram         text not null,
  nickname          text,
  nome_exibicao     text generated always as
                      (coalesce(nullif(btrim(nickname), ''), '@' || instagram)) stored,
  lions_saldo       int not null default 300,
  lions_renovado_em date not null default public.hoje(),
  pontuacao_total   numeric(8,2) not null default 0,
  papel             text not null default 'jogador' check (papel in ('jogador', 'admin')),
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  constraint instagram_valido check (instagram ~ '^[a-z0-9._]{1,30}$'),
  constraint nickname_valido  check (nickname is null or btrim(nickname) = '' or length(btrim(nickname)) between 2 and 20)
);

create unique index perfis_instagram_unico on public.perfis (lower(instagram));
create index perfis_pontuacao on public.perfis (pontuacao_total desc);

-- Cria o perfil automaticamente quando o usuário se cadastra.
-- O @ e o nickname vêm dos metadados enviados na tela de cadastro.
create or replace function public.fn_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_instagram text;
  v_nickname  text;
begin
  v_instagram := lower(regexp_replace(coalesce(new.raw_user_meta_data ->> 'instagram', ''), '^@', ''));
  v_nickname  := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'nickname', '')), '');

  insert into public.perfis (id, instagram, nickname, lions_saldo, lions_renovado_em)
  values (new.id, v_instagram, v_nickname, public.parametro_int('lions_dia_gratuito'), public.hoje());

  insert into public.transacoes_lions (usuario_id, tipo, quantidade, saldo_depois, referencia)
  values (new.id, 'renovacao', public.parametro_int('lions_dia_gratuito'),
          public.parametro_int('lions_dia_gratuito'), 'cadastro');

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- jogos — catálogo. Cada jogo novo é um INSERT, não uma coluna nova.
-- ---------------------------------------------------------------------------
create table public.jogos (
  id                    smallserial primary key,
  slug                  text unique not null,
  nome                  text not null,
  descricao             text,
  nivel                 text not null check (nivel in ('junior', 'pleno', 'senior')),
  custo_lions           int not null,
  pontuacao_maxima      numeric(4,2) not null,
  tempo_ideal_s         numeric(6,2),
  tempo_limite_s        numeric(6,2),
  pesos                 jsonb not null default '{"tempo":0.5,"execucao":0.3,"coleta":0.2}',
  arquivo               text,
  ativo                 boolean not null default false,
  exclusivo_cotista_ate date,
  criado_em             timestamptz not null default now(),
  constraint pontuacao_bate_com_nivel check (
    (nivel = 'junior' and pontuacao_maxima = 2) or
    (nivel = 'pleno'  and pontuacao_maxima = 4) or
    (nivel = 'senior' and pontuacao_maxima = 6)
  )
);

-- ---------------------------------------------------------------------------
-- pontuacoes — melhor marca de cada jogador em cada jogo, por temporada
-- ---------------------------------------------------------------------------
create table public.pontuacoes (
  usuario_id       uuid not null references public.perfis(id) on delete cascade,
  jogo_id          smallint not null references public.jogos(id) on delete cascade,
  temporada_id     smallint not null references public.temporadas(id),
  melhor_pontuacao numeric(4,2) not null default 0,
  melhor_tempo_s   numeric(6,2),
  partidas         int not null default 0,
  atualizado_em    timestamptz not null default now(),
  primary key (usuario_id, jogo_id, temporada_id)
);

create index pontuacoes_temporada on public.pontuacoes (temporada_id, melhor_pontuacao desc);

-- ---------------------------------------------------------------------------
-- partidas — log de cada tentativa (tabela de maior volume)
-- ---------------------------------------------------------------------------
create table public.partidas (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.perfis(id) on delete cascade,
  jogo_id         smallint not null references public.jogos(id),
  temporada_id    smallint not null references public.temporadas(id),
  semente         bigint not null,
  custo_lions     int not null,
  iniciada_em     timestamptz not null default now(),
  finalizada_em   timestamptz,
  duracao_s       numeric(6,2),
  pontuacao       numeric(4,2),
  metricas        jsonb,
  status          text not null default 'aberta'
                    check (status in ('aberta', 'concluida', 'abandonada', 'rejeitada')),
  motivo_rejeicao text
);

create index partidas_usuario on public.partidas (usuario_id, iniciada_em desc);
create index partidas_jogo    on public.partidas (jogo_id, status);

-- ---------------------------------------------------------------------------
-- transacoes_lions — extrato de créditos
-- ---------------------------------------------------------------------------
create table public.transacoes_lions (
  id           bigserial primary key,
  usuario_id   uuid not null references public.perfis(id) on delete cascade,
  tipo         text not null check (tipo in ('renovacao', 'debito', 'bonus', 'ajuste')),
  quantidade   int not null,
  saldo_depois int not null,
  referencia   text,
  criado_em    timestamptz not null default now()
);

create index transacoes_usuario on public.transacoes_lions (usuario_id, criado_em desc);

-- ---------------------------------------------------------------------------
-- pagamentos — tudo que a Cakto informar, com trava de evento repetido
-- ---------------------------------------------------------------------------
create table public.pagamentos (
  id             uuid primary key default gen_random_uuid(),
  provedor       text not null default 'cakto',
  evento_id      text not null,
  tipo_evento    text,
  usuario_id     uuid references public.perfis(id) on delete set null,
  plano_id       smallint references public.planos(id),
  valor_centavos int,
  status         text not null default 'recebido',
  payload        jsonb,
  processado_em  timestamptz,
  criado_em      timestamptz not null default now(),
  unique (provedor, evento_id)
);

-- ---------------------------------------------------------------------------
-- cotas — período pago. Uma ativa por usuário, garantida pelo índice.
-- ---------------------------------------------------------------------------
create table public.cotas (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references public.perfis(id) on delete cascade,
  plano_id     smallint not null references public.planos(id),
  inicio       date not null,
  fim          date not null,
  status       text not null default 'ativa'
                 check (status in ('ativa', 'expirada', 'cancelada', 'estornada')),
  pagamento_id uuid references public.pagamentos(id),
  criado_em    timestamptz not null default now(),
  check (fim >= inicio)
);

create unique index cotas_uma_ativa_por_usuario on public.cotas (usuario_id) where status = 'ativa';

-- ---------------------------------------------------------------------------
-- logs — eventos de sistema, separados do cadastro por causa do volume
-- ---------------------------------------------------------------------------
create table public.logs (
  id         bigserial primary key,
  usuario_id uuid,
  evento     text not null,
  detalhe    jsonb,
  criado_em  timestamptz not null default now()
);

create index logs_data on public.logs (criado_em desc);

-- ============================================================================
-- Regras de negócio (executadas no servidor, nunca no navegador)
-- ============================================================================

-- Lions disponíveis por dia para um usuário: 900 com cota ativa, 300 sem.
create or replace function public.fn_lions_dia(p_usuario uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select pl.lions_dia
       from public.cotas c
       join public.planos pl on pl.id = c.plano_id
      where c.usuario_id = p_usuario
        and c.status = 'ativa'
        and public.hoje() between c.inicio and c.fim
      limit 1),
    public.parametro_int('lions_dia_gratuito')
  );
$$;

-- Renovação preguiçosa: acontece no primeiro acesso do dia, não por agendador.
-- Saldo antigo não acumula — o novo dia sempre começa com o valor cheio.
create or replace function public.fn_sincronizar_lions(p_usuario uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil public.perfis%rowtype;
  v_dia    int;
begin
  update public.cotas
     set status = 'expirada'
   where usuario_id = p_usuario
     and status = 'ativa'
     and fim < public.hoje();

  select * into v_perfil from public.perfis where id = p_usuario for update;
  if not found then
    raise exception 'perfil inexistente';
  end if;

  if v_perfil.lions_renovado_em >= public.hoje() then
    return v_perfil.lions_saldo;
  end if;

  v_dia := public.fn_lions_dia(p_usuario);

  update public.perfis
     set lions_saldo = v_dia,
         lions_renovado_em = public.hoje()
   where id = p_usuario;

  insert into public.transacoes_lions (usuario_id, tipo, quantidade, saldo_depois, referencia)
  values (p_usuario, 'renovacao', v_dia, v_dia, 'virada diária');

  return v_dia;
end;
$$;

-- Tudo que o painel precisa, em uma chamada só.
create or replace function public.fn_meu_painel()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_saldo  int;
  v_perfil public.perfis%rowtype;
  v_cota   json;
begin
  if v_uid is null then
    raise exception 'sem sessão';
  end if;

  v_saldo := public.fn_sincronizar_lions(v_uid);
  select * into v_perfil from public.perfis where id = v_uid;

  select json_build_object(
           'plano',           pl.nome,
           'inicio',          c.inicio,
           'fim',             c.fim,
           'dias_restantes',  (c.fim - public.hoje()),
           'lions_dia',       pl.lions_dia
         )
    into v_cota
    from public.cotas c
    join public.planos pl on pl.id = c.plano_id
   where c.usuario_id = v_uid and c.status = 'ativa'
   limit 1;

  return json_build_object(
    'id',              v_perfil.id,
    'instagram',       v_perfil.instagram,
    'nickname',        v_perfil.nickname,
    'nome_exibicao',   v_perfil.nome_exibicao,
    'lions_saldo',     v_saldo,
    'lions_dia',       public.fn_lions_dia(v_uid),
    'pontuacao_total', v_perfil.pontuacao_total,
    'membro_desde',    v_perfil.criado_em,
    'cotista',         (v_cota is not null),
    'cota',            v_cota,
    'alerta_fim_cota', public.parametro_int('alerta_fim_cota'),
    'temporada',       (select nome from public.temporadas where id = public.temporada_atual())
  );
end;
$$;

-- Troca de nickname (só o dono, com as mesmas regras do cadastro).
create or replace function public.fn_alterar_nickname(p_nickname text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := nullif(btrim(p_nickname), '');
begin
  if v_uid is null then
    raise exception 'sem sessão';
  end if;
  if v_novo is not null and length(v_novo) not between 2 and 20 then
    raise exception 'O nome precisa ter de 2 a 20 caracteres.';
  end if;

  update public.perfis set nickname = v_novo where id = v_uid;
  return (select nome_exibicao from public.perfis where id = v_uid);
end;
$$;

-- ============================================================================
-- Rankings (leitura pública — servem também para divulgação no Instagram)
-- ============================================================================
create view public.v_ranking_geral as
select
  row_number() over (order by p.pontuacao_total desc, p.criado_em) as posicao,
  p.id,
  p.nome_exibicao,
  p.pontuacao_total,
  exists (
    select 1 from public.cotas c
     where c.usuario_id = p.id and c.status = 'ativa'
  ) as cotista
from public.perfis p
where p.ativo;

create view public.v_ranking_cotistas as
select row_number() over (order by pontuacao_total desc) as posicao, id, nome_exibicao, pontuacao_total
from public.v_ranking_geral where cotista;

create view public.v_ranking_seguidores as
select row_number() over (order by pontuacao_total desc) as posicao, id, nome_exibicao, pontuacao_total
from public.v_ranking_geral where not cotista;

-- Espelho para a planilha: uma linha por jogador, uma coluna por jogo.
-- (A consulta é montada na Etapa 2, quando existir o primeiro jogo.)
create view public.v_exportacao_cadastro as
select
  p.id,
  p.instagram,
  p.nome_exibicao,
  p.criado_em::date            as cadastro,
  p.pontuacao_total,
  p.lions_saldo,
  case when exists (select 1 from public.cotas c where c.usuario_id = p.id and c.status = 'ativa')
       then 'cotista' else 'seguidor' end as tipo
from public.perfis p;

-- ============================================================================
-- Gatilho de criação de perfil (por último: depende das tabelas acima)
-- ============================================================================
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.fn_novo_usuario();

-- Consulta pública usada na tela de cadastro para avisar antes de enviar
-- que aquele @ já está em uso (evita erro seco depois do clique).
create or replace function public.fn_instagram_disponivel(p_instagram text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.perfis
     where lower(instagram) = lower(regexp_replace(coalesce(p_instagram, ''), '^@', ''))
  );
$$;
