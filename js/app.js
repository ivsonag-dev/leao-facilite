/* ==========================================================================
   LEÃO FACILITE — Etapa 1
   Cadastro, confirmação de e-mail, login e painel.

   Regra que vale para todo o projeto: o navegador não decide nada que valha
   ponto ou crédito. Saldo, pontuação e cota vêm do servidor.
   ========================================================================== */

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const cfg = window.LEAO_CONFIG || {};
const configurado =
  cfg.SUPABASE_URL &&
  !cfg.SUPABASE_URL.startsWith("COLE_AQUI") &&
  cfg.SUPABASE_ANON_KEY &&
  !cfg.SUPABASE_ANON_KEY.startsWith("COLE_AQUI");

const sb = configurado ? createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;

/* ------------------------------------------------------------- utilidades */
const $ = (id) => document.getElementById(id);

function tela(nome) {
  document.querySelectorAll(".tela").forEach((t) => t.classList.remove("ativa"));
  $("tela-" + nome).classList.add("ativa");
  window.scrollTo(0, 0);
}

function aviso(id, texto, tipo = "ruim") {
  const el = $(id);
  el.className = "aviso ver " + tipo;
  el.textContent = texto;
}

function limparAviso(id) {
  $(id).className = "aviso";
  $(id).textContent = "";
}

function marcarErro(idCampo, texto) {
  const campo = $(idCampo);
  campo.classList.add("erro");
  if (texto) campo.querySelector(".msg-erro").textContent = texto;
}

function limparErros(...ids) {
  ids.forEach((id) => $(id).classList.remove("erro"));
}

function ocupado(botao, estado, textoOcupado) {
  if (estado) {
    botao.dataset.texto = botao.textContent;
    botao.textContent = textoOcupado;
    botao.disabled = true;
  } else {
    botao.textContent = botao.dataset.texto || botao.textContent;
    botao.disabled = false;
  }
}

const numero = (v, casas = 0) =>
  Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });

const emailValido = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test((v || "").trim());
const instagramValido = (v) => /^[a-zA-Z0-9._]{1,30}$/.test((v || "").trim());

/* Traduz os erros do Supabase para algo que o jogador entenda. */
function traduzir(erro) {
  const m = (erro?.message || "").toLowerCase();
  if (m.includes("invalid login credentials")) return "E-mail ou senha incorretos.";
  if (m.includes("email not confirmed")) return "Confirme seu e-mail antes de entrar.";
  if (m.includes("user already registered")) return "Este e-mail já tem cadastro. Tente entrar.";
  if (m.includes("password should be")) return "A senha precisa ter pelo menos 8 caracteres.";
  if (m.includes("rate limit") || m.includes("too many"))
    return "Muitas tentativas seguidas. Espere um minuto e tente de novo.";
  if (m.includes("database error")) return "Não foi possível criar o cadastro. Verifique o @ informado.";
  return erro?.message || "Algo deu errado. Tente novamente.";
}

/* ------------------------------------------------------------- navegação */
$("ir-cadastro").onclick = (e) => { e.preventDefault(); tela("cadastro"); };
$("ir-entrar").onclick = (e) => { e.preventDefault(); tela("entrar"); };
$("confirmado-entrar").onclick = (e) => { e.preventDefault(); tela("entrar"); };
$("ver-termos").onclick = (e) => { e.preventDefault(); $("modal-termos").classList.add("ver"); };
$("fechar-termos").onclick = () => $("modal-termos").classList.remove("ver");
$("modal-termos").onclick = (e) => { if (e.target.id === "modal-termos") e.currentTarget.classList.remove("ver"); };

/* ------------------------------------------------------------- cadastro */
$("btn-cadastrar").onclick = async () => {
  limparAviso("aviso-cadastro");
  limparErros("c-instagram", "c-email", "c-nickname", "c-senha");

  const instagram = $("cad-instagram").value.trim().replace(/^@/, "");
  const email = $("cad-email").value.trim();
  const nickname = $("cad-nickname").value.trim();
  const senha = $("cad-senha").value;

  let ok = true;
  if (!instagramValido(instagram)) {
    marcarErro("c-instagram", "Use apenas letras, números, ponto e underline.");
    ok = false;
  }
  if (!emailValido(email)) { marcarErro("c-email"); ok = false; }
  if (nickname && (nickname.length < 2 || nickname.length > 20)) { marcarErro("c-nickname"); ok = false; }
  if (senha.length < 8) { marcarErro("c-senha"); ok = false; }
  if (!$("cad-aceite").checked) {
    aviso("aviso-cadastro", "Para criar o cadastro é preciso aceitar os termos.");
    ok = false;
  }
  if (!ok) return;

  const botao = $("btn-cadastrar");
  ocupado(botao, true, "Criando...");

  try {
    const { data: livre, error: erroCheck } = await sb.rpc("fn_instagram_disponivel", {
      p_instagram: instagram
    });
    if (!erroCheck && livre === false) {
      marcarErro("c-instagram", "Este @ já está cadastrado na plataforma.");
      ocupado(botao, false);
      return;
    }

    const { error } = await sb.auth.signUp({
      email,
      password: senha,
      options: {
        data: { instagram: instagram.toLowerCase(), nickname: nickname || null },
        emailRedirectTo: cfg.URL_SITE
      }
    });

    if (error) {
      aviso("aviso-cadastro", traduzir(error));
      ocupado(botao, false);
      return;
    }

    $("email-enviado").textContent = email;
    sessionStorage.setItem("leao_email", email);
    ocupado(botao, false);
    tela("confirmar");
  } catch (e) {
    aviso("aviso-cadastro", "Falha de conexão. Verifique sua internet e tente de novo.");
    ocupado(botao, false);
  }
};

/* --------------------------------------------------------- reenvio do link */
$("btn-reenviar").onclick = async () => {
  const email = sessionStorage.getItem("leao_email");
  if (!email) { tela("cadastro"); return; }

  const botao = $("btn-reenviar");
  ocupado(botao, true, "Enviando...");
  const { error } = await sb.auth.resend({
    type: "signup",
    email,
    options: { emailRedirectTo: cfg.URL_SITE }
  });
  ocupado(botao, false);

  if (error) aviso("aviso-confirmar", traduzir(error));
  else aviso("aviso-confirmar", "Link reenviado. Confira sua caixa de entrada.", "bom");
};

/* ------------------------------------------------------------- entrar */
async function entrar() {
  limparAviso("aviso-entrar");
  limparErros("c-entrar-email", "c-entrar-senha");

  const email = $("entrar-email").value.trim();
  const senha = $("entrar-senha").value;

  let ok = true;
  if (!emailValido(email)) { marcarErro("c-entrar-email"); ok = false; }
  if (!senha) { marcarErro("c-entrar-senha"); ok = false; }
  if (!ok) return;

  const botao = $("btn-entrar");
  ocupado(botao, true, "Entrando...");
  const { error } = await sb.auth.signInWithPassword({ email, password: senha });
  ocupado(botao, false);

  if (error) {
    if ((error.message || "").toLowerCase().includes("email not confirmed")) {
      sessionStorage.setItem("leao_email", email);
      $("email-enviado").textContent = email;
      tela("confirmar");
      aviso("aviso-confirmar", "Sua conta ainda não foi confirmada.", "ouro");
      return;
    }
    aviso("aviso-entrar", traduzir(error));
    return;
  }
  abrirPainel();
}

$("btn-entrar").onclick = entrar;
$("entrar-senha").addEventListener("keydown", (e) => { if (e.key === "Enter") entrar(); });

/* ------------------------------------------------------- recuperar senha */
$("btn-esqueci").onclick = async () => {
  const email = $("entrar-email").value.trim();
  if (!emailValido(email)) {
    marcarErro("c-entrar-email", "Digite seu e-mail aqui e clique de novo.");
    return;
  }
  const botao = $("btn-esqueci");
  ocupado(botao, true, "Enviando...");
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: cfg.URL_SITE });
  ocupado(botao, false);
  if (error) aviso("aviso-entrar", traduzir(error));
  else aviso("aviso-entrar", "Enviamos um link de redefinição para o seu e-mail.", "bom");
};

/* ------------------------------------------------------------- painel */
async function abrirPainel() {
  tela("painel");

  const { data, error } = await sb.rpc("fn_meu_painel");
  if (error) {
    aviso("alerta-cota", "Não conseguimos carregar seus dados agora. Recarregue a página.", "ruim");
    $("alerta-cota").classList.add("ver");
    return;
  }

  $("p-nome").textContent = data.nome_exibicao;
  $("p-lions").textContent = numero(data.lions_saldo);
  $("p-pontos").textContent = numero(data.pontuacao_total, 2);
  $("p-temporada").innerHTML = data.temporada ? `<small>na temporada de ${data.temporada}</small>` : "";
  $("p-nickname").value = data.nickname || "";

  const tipo = $("p-tipo");
  if (data.cotista) {
    tipo.innerHTML = '<span class="etiqueta cotista">Cotista</span>';
    $("p-lions-legenda").textContent =
      `Sua cota garante ${numero(data.cota.lions_dia)} Lions por dia. Renova à meia-noite e não acumula.`;
    $("p-cota-conteudo").innerHTML = `
      <div class="destaque">${data.cota.dias_restantes}<small>dias restantes</small></div>
      <p style="margin-top:8px">${data.cota.plano}, válida até
        ${new Date(data.cota.fim + "T12:00:00").toLocaleDateString("pt-BR")}.</p>`;
    $("btn-cota").textContent = "Ver o calendário da cota";

    if (data.cota.dias_restantes <= data.alerta_fim_cota) {
      const a = $("alerta-cota");
      a.className = "aviso ver ouro";
      a.textContent =
        data.cota.dias_restantes <= 0
          ? "Sua cota termina hoje. Renove para continuar com 900 Lions por dia."
          : `Sua cota termina em ${data.cota.dias_restantes} dia(s). Renove para não voltar aos 300 Lions.`;
    }
  } else {
    tipo.innerHTML = '<span class="etiqueta">Seguidor</span>';
    $("p-lions-legenda").textContent =
      `Seu saldo de hoje. Renova à meia-noite com ${numero(data.lions_dia)} Lions e não acumula.`;
    $("p-cota-conteudo").innerHTML =
      `<p>Você joga com ${numero(data.lions_dia)} Lions por dia. A cota mensal triplica esse saldo.</p>`;
  }
}

$("btn-nickname").onclick = async () => {
  limparErros("c-nickname-painel");
  $("p-nickname-ok").style.display = "none";
  const valor = $("p-nickname").value.trim();
  if (valor && (valor.length < 2 || valor.length > 20)) {
    marcarErro("c-nickname-painel");
    return;
  }
  const botao = $("btn-nickname");
  ocupado(botao, true, "Salvando...");
  const { data, error } = await sb.rpc("fn_alterar_nickname", { p_nickname: valor });
  ocupado(botao, false);
  if (error) { alert(traduzir(error)); return; }
  $("p-nome").textContent = data;
  $("p-nickname-ok").style.display = "block";
};

$("btn-cota").onclick = () => {
  alert("A compra da cota entra na Etapa 5, junto com a integração de pagamento.");
};

$("btn-sair").onclick = async () => {
  await sb.auth.signOut();
  tela("entrar");
};

/* ------------------------------------------------------------- início */
(async function iniciar() {
  if (!configurado) {
    aviso(
      "aviso-entrar",
      "Configuração pendente: preencha js/config.js com a URL e a chave anon do Supabase.",
      "ouro"
    );
    return;
  }

  // Quem chega pelo link de confirmação do e-mail já vem com sessão criada.
  const { data } = await sb.auth.getSession();
  if (data.session) {
    if (window.location.hash) history.replaceState(null, "", window.location.pathname);
    abrirPainel();
  }
})();
