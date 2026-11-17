"use strict";

const people = [
  { id: 1, name: "Marina Costa", role: "Engenheira iOS", area: "Mobile", skills: ["Swift", "SwiftUI"], location: "Fortaleza, CE" },
  { id: 2, name: "Camila Lima", role: "Dev Back-end", area: "Back-end", skills: ["Python", "APIs REST"], location: "Recife, PE" },
  { id: 3, name: "Luana Alves", role: "Dev Front-end", area: "Front-end", skills: ["React", "Acessibilidade"], location: "São Paulo, SP" }
];
const groups = [
  { id: 1, title: "Swift em prática", description: "Construa uma tela com SwiftUI em conjunto.", days: 3, participants: 12 },
  { id: 2, title: "APIs sem mistério", description: "Pratique requisições, decodificação e estados de erro.", days: 5, participants: 8 }
];
const jobs = [
  { id: 1, title: "Dev iOS", company: "Estúdio Aurora", level: "Júnior", mode: "Remoto" },
  { id: 2, title: "Dev Back-end", company: "Nuvem Labs", level: "Pleno", mode: "Híbrido" },
  { id: 3, title: "Dev Front-end", company: "Órbita Digital", level: "Sênior", mode: "Presencial" }
];
const topicCatalog = [
  { id: 1, title: "Primeira tela com SwiftUI", body: "Como vocês organizam as primeiras telas para que o projeto continue fácil de manter?", category: "Front-end" },
  { id: 2, title: "Tratamento de erros em APIs", body: "Quais estratégias vocês usam para transformar falhas de rede em mensagens que ajudam quem usa o app?", category: "Back-end" },
  { id: 3, title: "Testando acessibilidade", body: "Que experiências vocês tiveram ao testar Dynamic Type e VoiceOver em projetos de interface?", category: "Front-end" },
  { id: 4, title: "Montando uma API para o portfólio", body: "Que recursos vocês escolheriam para praticar autenticação e paginação?", category: "Back-end" }
];

const screen = document.querySelector("#screen");
const editor = document.querySelector("#editor");
const feedback = document.querySelector("#feedback");
const storageKey = "codegirls.web.v1";
const dateFormat = new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium", timeStyle: "short" });
const afterDays = days => Date.now() + days * 86_400_000;
const emptyNetwork = { area: "", skills: "", location: "" };
const filters = { query: "", category: "", network: emptyNetwork, level: new Set(), mode: new Set() };
const forum = { status: "idle", topics: [] };
let active = "inicio";
let feedbackTimer;
let profile = { name: "Raissa", photo: "", connections: [1], joined: [], saved: [1], sessions: { 1: afterDays(7) } };
try {
  profile = { ...profile, ...JSON.parse(localStorage.getItem(storageKey)) };
} catch {
  // A interface continua utilizável quando o navegador bloqueia o armazenamento.
}

function persist() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(profile));
    return true;
  } catch {
    announce("O navegador não conseguiu salvar esta alteração para a próxima visita.");
    return false;
  }
}

function escape(value) {
  return String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function includes(text, search) {
  const normalize = value => value.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase();
  return normalize(text).includes(normalize(search));
}

function announce(message) {
  clearTimeout(feedbackTimer);
  feedback.textContent = message;
  feedbackTimer = setTimeout(() => { feedback.textContent = ""; }, 3600);
}

function toggle(items, id) {
  return items.includes(id) ? items.filter(item => item !== id) : [...items, id];
}

const heading = (title, description) => `<header class="page-heading"><h1>${title}</h1><p>${description}</p></header>`;
const section = (title, content) => `<section class="section"><h2>${title}</h2>${content}</section>`;
const tags = items => `<div class="tags">${items.map(item => `<span class="tag">${escape(item)}</span>`).join("")}</div>`;
const button = (label, action, id = "", primary = false) => `<button type="button" class="button${primary ? " primary" : ""}" data-action="${action}" data-id="${id}">${label}</button>`;
const field = (label, name, value = "", type = "text") => `<label class="field">${label}<input type="${type}" name="${name}" value="${escape(value)}"></label>`;
const empty = message => `<p class="muted">${message}</p>`;
const dateLabel = date => dateFormat.format(new Date(date));
const personLine = person => `<div class="person"><span class="avatar" aria-hidden="true">${person.name[0]}</span><div><h3>${person.name}</h3><div class="muted">${person.role} · ${person.location}</div></div></div>`;

function home() {
  const next = people.map(person => ({ person, date: profile.sessions[person.id] }))
    .filter(item => item.date >= Date.now()).sort((a, b) => a.date - b.date)[0];
  const photo = /^data:image\/(?:png|jpe?g|webp);base64,/i.test(profile.photo)
    ? `<img alt="" src="${escape(profile.photo)}">`
    : escape(profile.name.slice(0, 1).toUpperCase());
  return `<section class="hero"><div class="hero-content">
      <h1>Bem-vinda, ${escape(profile.name)}</h1>
      <p>Seu espaço para trocar experiências com mulheres em tecnologia.</p>
      <a class="button primary" href="#foruns">Explorar fóruns</a>
    </div></section>
    <div class="stats" aria-label="Resumo da comunidade">
      <a href="#foruns"><span class="value" id="forum-count">${forum.status === "success" ? forum.topics.length : "—"}</span><span>Fóruns</span></a>
      <a href="#network"><span class="value">${profile.connections.length}</span><span>Conexões</span></a>
      <a href="#mentoria"><span class="value">${Object.keys(profile.sessions).length}</span><span>Mentorias</span></a>
    </div>
    <div class="columns">
      <section class="card"><h2>Notificações</h2>
        ${next ? `<p>Mentoria com ${next.person.name}</p><p class="muted">${dateLabel(next.date)}</p>` : ""}
        <p><a href="#grupos">Explore os próximos grupos de estudo</a></p>
      </section>
      <section class="card"><div class="person"><span class="avatar" aria-hidden="true">${photo}</span><div><h2>Seu perfil</h2><p class="muted">Dev Full Stack</p></div></div>
        <div class="actions">${button("Editar perfil", "profile")}</div>
      </section>
    </div>`;
}

function forums() {
  return `${heading("Fóruns", "Compartilhe experiências e tire dúvidas com a comunidade.")}
    <div class="filters grid">
      ${field("Buscar tópicos", "query", filters.query, "search")}
      <label class="field">Categoria<select name="category">
        ${["", "Front-end", "Back-end"].map(category => `<option value="${category}"${filters.category === category ? " selected" : ""}>${category || "Todos"}</option>`).join("")}
      </select></label>
    </div>
    <div id="topics" class="stack" aria-live="polite"></div>`;
}

function updateTopics() {
  const list = document.querySelector("#topics");
  const count = document.querySelector("#forum-count");
  if (count) count.textContent = forum.status === "success" ? forum.topics.length : "—";
  if (!list) return;
  if (forum.status === "loading" || forum.status === "idle") {
    list.textContent = "Carregando tópicos…";
    return;
  }
  if (forum.status === "error") {
    list.innerHTML = `<div class="card"><p>Não foi possível carregar os tópicos. Verifique sua conexão.</p><div class="actions">${button("Tentar novamente", "refresh", "", true)}</div></div>`;
    return;
  }
  const visible = forum.topics.filter(topic => (!filters.category || filters.category === topic.category)
    && includes(`${topic.title} ${topic.body}`, filters.query));
  list.innerHTML = `<div>${button("Atualizar tópicos", "refresh")}</div>` + (visible.map(topic =>
    `<article class="card topic"><span class="tag">${topic.category}</span><h3>${topic.title}</h3><p class="muted">${topic.body}</p></article>`
  ).join("") || empty("Nenhum tópico encontrado com essa busca."));
}

async function loadForums() {
  if (forum.status === "loading") return;
  forum.status = "loading";
  updateTopics();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch("https://jsonplaceholder.typicode.com/posts", { cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error("HTTP " + response.status);
    const posts = await response.json();
    if (!Array.isArray(posts)) throw new Error("Formato inesperado");
    const ids = new Set(posts.map(post => post.id));
    forum.topics = topicCatalog.filter(topic => ids.has(topic.id));
    forum.status = "success";
  } catch {
    forum.status = "error";
  } finally {
    clearTimeout(timeout);
    updateTopics();
  }
}

function network() {
  const criteria = filters.network;
  const skills = criteria.skills.split(",").map(item => item.trim()).filter(Boolean);
  const connected = people.filter(person => profile.connections.includes(person.id));
  const suggested = people.filter(person => !profile.connections.includes(person.id)
    && includes(person.area, criteria.area) && includes(person.location, criteria.location)
    && skills.every(skill => person.skills.some(item => includes(item, skill))));
  return `${heading("Network", "Conheça profissionais com interesses e habilidades em comum.")}
    <div class="columns">
      <section><h2>Conexões</h2><div class="section stack">
      ${connected.map(person => `<article class="card">${personLine(person)}</article>`).join("") || empty("Suas conexões aparecerão aqui.")}
      </div></section>
      <form id="network-filters" class="filters">
        <h2>Filtrar perfis</h2>
        ${field("Área", "area", criteria.area)}
        ${field("Habilidades, separadas por vírgula", "skills", criteria.skills)}
        ${field("Localização", "location", criteria.location)}
        <div class="actions"><button class="button primary">Aplicar filtros</button>${button("Limpar filtros", "clear-network")}</div>
      </form>
    </div>
    ${section("Conheça outras profissionais", `<div class="grid">${suggested.map(person =>
      `<article class="card">${personLine(person)}${tags(person.skills)}<div class="actions">${button("Conectar", "connect", person.id, true)}</div></article>`
    ).join("") || empty("Nenhuma sugestão com esses filtros.")}</div>`)}`;
}

function studyGroups() {
  return `${heading("Grupos", "Encontre um grupo para praticar e aprender em conjunto.")}
    ${section("Próximos encontros", `<div class="grid">${groups.map(group => {
      const joined = profile.joined.includes(group.id);
      return `<article class="card"><h3>${group.title}</h3><p>${group.description}</p>
        <p class="muted">${dateLabel(afterDays(group.days))} · ${group.participants + Number(joined)} participantes</p>
        <div class="actions">${button(joined ? "Sair do grupo" : "Participar", "join", group.id, !joined)}</div></article>`;
    }).join("")}</div>`)}`;
}

function opening(job) {
  const saved = profile.saved.includes(job.id);
  return `<article class="card"><h3>${job.title}</h3><p class="muted">${job.company}</p>${tags([job.level, job.mode])}
    <div class="actions">${button(saved ? "Remover dos salvos" : "Salvar vaga", "save-job", job.id, !saved)}
    ${button("Compartilhar vaga", "share-job", job.id)}</div></article>`;
}

function availableJobCards() {
  const available = jobs.filter(job => (!filters.level.size || filters.level.has(job.level))
    && (!filters.mode.size || filters.mode.has(job.mode)));
  return available.map(opening).join("") || empty("Nenhuma vaga com esses filtros.");
}

function vacancies() {
  const checks = (label, key, options) => `<fieldset><legend>${label}</legend><div class="checks">${options.map(option =>
    `<label><input type="checkbox" name="${key}" value="${option}"${filters[key].has(option) ? " checked" : ""}> ${option}</label>`
  ).join("")}</div></fieldset>`;
  const saved = jobs.filter(job => profile.saved.includes(job.id));
  return `${heading("Vagas", "Filtre oportunidades e salve as que combinam com seu perfil.")}
    <div class="filters">${checks("Nível", "level", ["Júnior", "Pleno", "Sênior"])}
    ${checks("Modalidade", "mode", ["Remoto", "Híbrido", "Presencial"])}
    <div class="actions">${button("Limpar filtros", "clear-jobs")}</div></div>
    <div class="columns">
      ${section("Vagas disponíveis", `<div class="stack" id="available">${availableJobCards()}</div>`)}
      ${section("Vagas salvas", `<div class="stack">${saved.map(opening).join("") || empty("Salve uma vaga para encontrá-la aqui.")}</div>`)}
    </div>`;
}

function mentorship() {
  const scheduled = people.filter(person => profile.sessions[person.id])
    .sort((a, b) => profile.sessions[a.id] - profile.sessions[b.id]);
  return `${heading("Mentoria", "Converse com profissionais sobre aprendizado e carreira.")}
    <div class="columns">
      ${section("Suas mentorias", `<div class="stack">${scheduled.map(person => `<article class="card">
        <h3>Encontro com ${person.name}</h3><p class="muted">${dateLabel(profile.sessions[person.id])}</p>
        <div class="actions">${button("Reagendar", "reschedule", person.id)}</div></article>`).join("")
        || empty("Suas mentorias agendadas aparecerão aqui.")}</div>`)}
      ${section("Conheça as mentoras", `<div class="stack">${people.map(person => `<article class="card">
        ${personLine(person)}${tags(person.skills)}<div class="actions">
        ${profile.sessions[person.id] ? "<span class=\"muted\">Mentoria agendada</span>" : button("Solicitar mentoria", "mentor", person.id, true)}
        </div></article>`).join("")}</div>`)}
    </div>`;
}

const routes = { inicio: home, foruns: forums, network, grupos: studyGroups, vagas: vacancies, mentoria: mentorship };
function render() {
  screen.innerHTML = routes[active]();
  updateTopics();
}

function navigate({ focus = false } = {}) {
  const target = location.hash.slice(1);
  if (target === "conteudo") {
    if (!screen.firstElementChild) {
      document.querySelector('nav a[href="#inicio"]').setAttribute("aria-current", "page");
      render();
    }
    document.querySelector("main").focus();
    return;
  }
  active = Object.hasOwn(routes, target) ? target : "inicio";
  for (const link of document.querySelectorAll("nav a")) {
    if (link.hash === "#" + active) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  render();
  if (focus) {
    window.scrollTo(0, 0);
    document.querySelector("main").focus({ preventScroll: true });
  }
}

function openProfile() {
  editor.innerHTML = `<h2 id="editor-title">Editar perfil</h2><form id="profile-form">
    <label class="field">Nome<input name="name" value="${escape(profile.name)}" required maxlength="60" autocomplete="given-name"></label>
    <label class="field">Foto de perfil<input type="file" name="photo" accept="image/png,image/jpeg,image/webp"></label>
    ${profile.photo ? '<label><input type="checkbox" name="remove"> Remover foto atual</label>' : ""}
    <p class="muted" data-error role="status"></p>
    <div class="actions">${button("Cancelar", "close")}<button class="button primary">Salvar</button></div></form>`;
  editor.showModal();
}

function openSchedule(person) {
  const appointment = new Date(Math.max(profile.sessions[person.id], Date.now() + 3600000));
  const local = new Date(appointment.getTime() - appointment.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  editor.innerHTML = `<h2 id="editor-title">Reagendar mentoria</h2><p class="muted">${person.name}</p>
    <form id="schedule" data-id="${person.id}"><label class="field">Nova data e hora
    <input name="date" type="datetime-local" value="${local}" required></label>
    <p class="muted" data-error role="status"></p>
    <div class="actions">${button("Cancelar", "close")}<button class="button primary">Salvar horário</button></div></form>`;
  editor.showModal();
}

async function saveProfile(form) {
  const data = new FormData(form);
  const name = data.get("name").trim();
  const file = data.get("photo");
  const error = form.querySelector("[data-error]");
  if (!name) {
    error.textContent = "Digite seu nome.";
    return;
  }
  let photo = data.has("remove") ? "" : profile.photo;
  if (file.size > 0) {
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size > 1_000_000) {
      error.textContent = "Escolha uma imagem PNG, JPG ou WebP de até 1 MB.";
      return;
    }
    try {
      photo = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
    } catch {
      error.textContent = "Não foi possível abrir a foto.";
      return;
    }
  }
  if (!editor.open || !form.isConnected) return;
  Object.assign(profile, { name, photo });
  editor.close();
  if (persist()) announce("Perfil atualizado.");
  render();
}

async function shareJob(job) {
  const text = `${job.title} · ${job.company}\n${job.level} · ${job.mode}\nVaga demonstrativa do CodeGirls`;
  const url = new URL("#vagas", location.href).href;
  try {
    if (navigator.share) await navigator.share({ title: job.title, text, url });
    else {
      await navigator.clipboard.writeText(`${text}\n${url}`);
      announce("Vaga copiada.");
    }
  } catch (error) {
    if (error.name !== "AbortError") announce("Não foi possível compartilhar a vaga.");
  }
}

document.addEventListener("click", event => {
  const target = event.target.closest("[data-action]");
  if (!target) return;
  const id = Number(target.dataset.id);
  switch (target.dataset.action) {
    case "profile": openProfile(); return;
    case "close": editor.close(); return;
    case "reschedule": openSchedule(people.find(person => person.id === id)); return;
    case "refresh": loadForums(); return;
    case "share-job": shareJob(jobs.find(job => job.id === id)); return;
    case "clear-network": filters.network = emptyNetwork; render(); return;
    case "clear-jobs": filters.level.clear(); filters.mode.clear(); render(); return;
    case "connect": profile.connections = [...new Set([...profile.connections, id])]; break;
    case "join": profile.joined = toggle(profile.joined, id); break;
    case "save-job": profile.saved = toggle(profile.saved, id); break;
    case "mentor": profile.sessions[id] = afterDays(6 + id); break;
    default: return;
  }
  persist();
  render();
});

document.addEventListener("submit", event => {
  const form = event.target;
  event.preventDefault();
  if (form.id === "network-filters") {
    filters.network = Object.fromEntries(new FormData(form));
    render();
  } else if (form.id === "profile-form") {
    saveProfile(form);
  } else if (form.id === "schedule") {
    const date = new Date(new FormData(form).get("date")).getTime();
    if (!Number.isFinite(date) || date <= Date.now()) {
      form.querySelector("[data-error]").textContent = "Escolha uma data e um horário futuros.";
      return;
    }
    profile.sessions[form.dataset.id] = date;
    editor.close();
    if (persist()) announce("Mentoria reagendada.");
    render();
  }
});

screen.addEventListener("input", event => {
  if (event.target.name === "query") {
    filters.query = event.target.value;
    updateTopics();
  }
});

screen.addEventListener("change", event => {
  const { name, value, checked } = event.target;
  if (name === "category") {
    filters.category = value;
    updateTopics();
  } else if (name === "level" || name === "mode") {
    if (checked) filters[name].add(value);
    else filters[name].delete(value);
    document.querySelector("#available").innerHTML = availableJobCards();
  }
});

window.addEventListener("hashchange", () => navigate({ focus: true }));
navigate();
loadForums();
