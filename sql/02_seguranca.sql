-- ============================================================================
-- LEÃO FACILITE — Etapa 1: segurança
-- Executar depois de 01_schema.sql.
--
-- Princípio: o navegador só LÊ o que é do próprio usuário (ou público).
-- Nenhuma escrita direta é permitida — saldo, pontuação e cota só mudam
-- através das funções do servidor. Isso é o que impede alguém de digitar
-- a própria pontuação pelo console.
-- ============================================================================

alter table public.perfis            enable row level security;
alter table public.pontuacoes        enable row level security;
alter table public.partidas          enable row level security;
alter table public.transacoes_lions  enable row level security;
alter table public.cotas             enable row level security;
alter table public.pagamentos        enable row level security;
alter table public.logs              enable row level security;
alter table public.jogos             enable row level security;
alter table public.planos            enable row level security;
alter table public.temporadas        enable row level security;
alter table public.parametros        enable row level security;

-- --------------------------------------------------------------------------
-- Cada um vê o que é seu
-- --------------------------------------------------------------------------
create policy perfil_proprio on public.perfis
  for select to authenticated using (id = auth.uid());

create policy pontuacoes_proprias on public.pontuacoes
  for select to authenticated using (usuario_id = auth.uid());

create policy partidas_proprias on public.partidas
  for select to authenticated using (usuario_id = auth.uid());

create policy transacoes_proprias on public.transacoes_lions
  for select to authenticated using (usuario_id = auth.uid());

create policy cotas_proprias on public.cotas
  for select to authenticated using (usuario_id = auth.uid());

-- pagamentos e logs: nenhuma política de leitura. Só o servidor enxerga.

-- --------------------------------------------------------------------------
-- Catálogo público
-- --------------------------------------------------------------------------
create policy jogos_publicos on public.jogos
  for select to anon, authenticated using (ativo);

create policy planos_publicos on public.planos
  for select to anon, authenticated using (ativo);

create policy temporadas_publicas on public.temporadas
  for select to anon, authenticated using (true);

create policy parametros_publicos on public.parametros
  for select to anon, authenticated
  using (chave in ('custo_junior', 'custo_pleno', 'custo_senior',
                   'lions_dia_gratuito', 'alerta_fim_cota', 'cadastro_aberto'));

-- --------------------------------------------------------------------------
-- Nenhuma escrita vinda do navegador
-- --------------------------------------------------------------------------
revoke insert, update, delete on all tables in schema public from anon, authenticated;

grant select on
  public.v_ranking_geral,
  public.v_ranking_cotistas,
  public.v_ranking_seguidores
to anon, authenticated;

revoke select on public.v_exportacao_cadastro from anon, authenticated;

-- --------------------------------------------------------------------------
-- Funções que o navegador pode chamar
-- --------------------------------------------------------------------------
revoke execute on function public.fn_sincronizar_lions(uuid) from anon, authenticated;
revoke execute on function public.fn_lions_dia(uuid)         from anon, authenticated;

grant execute on function public.fn_meu_painel()            to authenticated;
grant execute on function public.fn_alterar_nickname(text)  to authenticated;
grant execute on function public.temporada_atual()          to anon, authenticated;
grant execute on function public.fn_instagram_disponivel(text) to anon, authenticated;
