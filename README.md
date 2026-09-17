# Leão Facilite — Etapa 1

Cadastro, confirmação de e-mail, login e painel do jogador, com o banco de dados completo
da plataforma já modelado.

## O que já funciona

- Cadastro com @ do Instagram, e-mail, nickname opcional e senha
- Confirmação de e-mail obrigatória, com reenvio do link
- Login, logout e recuperação de senha
- Criação automática do perfil com 300 Lions
- Renovação diária de Lions no fuso de Recife, sem acúmulo
- Painel com saldo, pontuação, situação da cota e troca de nickname
- Alerta automático nos últimos 5 dias de cota

## O que ainda não funciona (etapas seguintes)

- Jogar, pontuar e ranking (Etapas 2, 3 e 4)
- Comprar cota pela Cakto (Etapa 5)

---

## Instalação

### 1. Criar o projeto no Supabase

1. Acesse supabase.com, crie uma conta e um projeto chamado `leao-facilite`.
2. Região: **South America (São Paulo)**.
3. Guarde a senha do banco que ele pedir.

### 2. Rodar o banco

No menu lateral, **SQL Editor** → New query:

1. Cole todo o conteúdo de `sql/01_schema.sql` e execute.
2. Abra outra query, cole `sql/02_seguranca.sql` e execute.

Ao final, em **Table Editor**, devem existir 11 tabelas.

### 3. Configurar a autenticação

Em **Authentication → Sign In / Providers → Email**:

- Confirm email: **ligado**
- Minimum password length: **8**

Em **Authentication → URL Configuration**:

- Site URL: o endereço do seu site (ex.: `https://seuusuario.github.io/leao-facilite/`)
- Redirect URLs: adicione o mesmo endereço

> O envio de e-mail nativo do Supabase tem limite baixo de mensagens por hora e serve
> para testes. Quando o cadastro começar a crescer, é preciso configurar um SMTP próprio
> em Authentication → Emails → SMTP Settings. Existem serviços com camada gratuita para
> esse volume; vale comparar os limites atuais antes de escolher.

### 4. Preencher as chaves

Em **Project Settings → API**, copie:

- Project URL
- Chave `anon` `public`

Cole em `js/config.js`, junto com o endereço público do site.

**Nunca** coloque a chave `service_role` nesse arquivo — ele é público.

### 5. Publicar

1. Crie o repositório `leao-facilite` no GitHub (público).
2. Envie estes arquivos mantendo a estrutura de pastas.
3. Settings → Pages → Source: branch `main`, pasta `/root`.

### 6. Logo

Salve o emblema como `assets/logo.png` (formato quadrado, fundo transparente ou escuro).
Enquanto o arquivo não existir, o site mostra o monograma desenhado em CSS.

---

## Estrutura do banco

| Tabela | Para que serve |
|---|---|
| `perfis` | Uma linha por jogador: @, nickname, saldo de Lions, pontuação total |
| `planos` | As cotas vendidas. Só a mensal está ativa |
| `cotas` | Períodos pagos. Índice garante uma ativa por usuário |
| `pagamentos` | Eventos da Cakto, com trava contra evento duplicado |
| `jogos` | Catálogo. Cada jogo novo é um registro, não uma coluna |
| `pontuacoes` | Melhor marca de cada jogador em cada jogo, por temporada |
| `partidas` | Log de cada tentativa |
| `transacoes_lions` | Extrato de créditos |
| `temporadas` | Ciclos mensais de ranking |
| `logs` | Eventos de sistema, separados por causa do volume |
| `parametros` | Valores de regra ajustáveis sem mexer em código |

### Por que uma tabela de pontuações em vez de uma coluna por jogo

Você imaginou uma coluna nova no cadastro a cada jogo criado. No banco isso obrigaria a
alterar a estrutura da tabela a cada lançamento e deixaria o ranking difícil de calcular.
A forma equivalente e mais segura é uma linha por jogador e jogo — e a visão
`v_exportacao_cadastro` devolve isso pivotado, uma coluna por jogo, exatamente como você
quer ver na planilha.

### Mudanças de regra sem código

```sql
-- Lions diários de quem não tem cota
update parametros set valor = '400' where chave = 'lions_dia_gratuito';

-- Abrir o plano trimestral
update planos set preco_centavos = 2700, ativo = true where slug = 'trimestral';

-- Fechar cadastros temporariamente
update parametros set valor = 'false' where chave = 'cadastro_aberto';
```

---

## Teste de aceitação da Etapa 1

1. Criar cadastro com um @ e um e-mail reais
2. Confirmar que o e-mail chega e que o link abre o painel já logado
3. Conferir 300 Lions e pontuação 0,00 no painel
4. Tentar criar outro cadastro com o mesmo @ → precisa ser bloqueado na tela
5. Sair, entrar de novo com e-mail e senha
6. Trocar o nickname e ver o nome mudar no topo
7. No Supabase, conferir a linha em `perfis` e o registro em `transacoes_lions`
