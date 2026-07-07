"use strict";
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => (s ?? "").replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const seasonKey = (s) => (s || "").trim().toLowerCase().replace(/\s+/g, "-");

const state = { days: [], selected: null, dirty: false, status: "" };

const READINGS = [
  ["reading_ja", "reading", "読み"],
  ["reading_en", "romaji", "ローマ字"],
  ["translation_en", "translation", "英訳"],
];

/* -------------------------------------------------------------- index list */
async function loadDays(keepSelection = true) {
  const params = new URLSearchParams();
  if ($("#from").value.trim()) params.set("from", $("#from").value.trim());
  if ($("#to").value.trim()) params.set("to", $("#to").value.trim());
  if (state.status) params.set("status", state.status);

  state.days = await (await fetch("/api/days?" + params)).json();
  renderIndex();
  renderProgress();
  if (keepSelection && state.selected &&
      state.days.some((d) => d.date === state.selected)) {
    highlightSelected();
  }
}

function renderIndex() {
  const ol = $("#days");
  ol.innerHTML = "";
  if (!state.days.length) {
    ol.innerHTML = `<li class="gallery__empty" style="margin:1rem .3rem">no days in range</li>`;
    return;
  }
  for (const d of state.days) {
    const li = document.createElement("li");
    li.className = "day";
    li.dataset.season = seasonKey(d.season);
    li.dataset.date = d.date;
    if (d.date === state.selected) li.classList.add("is-selected");
    const [mmdd, yyyy] = fmtDate(d.date);
    li.innerHTML = `
      <span class="day__date">${yyyy}<b>${mmdd}</b></span>
      <span class="day__word">
        <span class="day__kanji">${esc(d.kanji) || "—"}</span>
        <span class="day__reading">${esc(d.reading_ja)}</span>
      </span>
      <span class="day__status">
        <span class="dot ${d.has_prose ? "on" : ""}" title="prose"></span>
        <span class="dot ${d.has_image ? "on" : ""}" title="image chosen"></span>
        ${d.approved ? `<span class="check" title="approved">✓</span>` : ""}
      </span>`;
    li.onclick = () => selectDay(d.date);
    ol.appendChild(li);
  }
}

function fmtDate(iso) {
  const [y, m, d] = iso.split("-");
  return [`${m}·${d}`, y];
}

function renderProgress() {
  const total = state.days.length;
  const done = state.days.filter((d) => d.approved).length;
  $("#progressNum").textContent = done;
  $("#progressDen").textContent = `/ ${total} approved`;
  const C = 119.38;
  $("#progressArc").style.strokeDashoffset = total ? C * (1 - done / total) : C;
}

function highlightSelected() {
  for (const li of document.querySelectorAll(".day"))
    li.classList.toggle("is-selected", li.dataset.date === state.selected);
}

/* ------------------------------------------------------------------ editor */
async function selectDay(date) {
  if (state.dirty && !confirm("Discard unsaved edits on this day?")) return;
  state.selected = date;
  state.dirty = false;
  highlightSelected();
  const day = await (await fetch("/api/days/" + date)).json();
  document.body.dataset.season = seasonKey(day.season);
  renderEditor(day);
}

function renderEditor(day) {
  $("#empty").hidden = true;
  const ed = $("#editor");
  ed.hidden = false;
  ed.dataset.season = seasonKey(day.season);

  const [mmdd, yyyy] = fmtDate(day.date);
  const tags = [
    `<span class="tag tag--date">${yyyy}·${mmdd}</span>`,
    day.season && `<span class="tag">${esc(day.season)}</span>`,
    day.subseason && `<span class="tag">${esc(day.subseason)}</span>`,
    day.category && `<span class="tag">${esc(day.category)}</span>`,
  ].filter(Boolean).join("");

  const readingFields = READINGS.map(([key, en, ja]) => `
    <div class="field">
      <label for="f-${key}">${en} <span class="ja">${ja}</span></label>
      <input class="control" id="f-${key}" data-key="${key}" type="text"
             value="${esc(day[key])}">
    </div>`).join("");

  ed.innerHTML = `
    <article class="entry" data-season="${seasonKey(day.season)}">
      <header class="hero">
        <div class="hero__kanji">${esc(day.kanji) || "—"}</div>
        <div>
          <div class="hero__reading">${esc(day.reading_ja)}</div>
          <div class="hero__romaji">${esc(day.reading_en)}</div>
          <div class="hero__gloss">${esc(day.gloss_en)}</div>
          <div class="hero__tags">${tags}</div>
        </div>
      </header>

      <div>
        <h2 class="sec-title">readings &amp; translation</h2>
        <div class="readings">${readingFields}</div>

        <h2 class="sec-title">descriptions</h2>
        <div class="pair">
          <div class="field">
            <label for="f-description_ja">Japanese <span class="ja">和文</span></label>
            <textarea class="control" id="f-description_ja" data-key="description_ja" lang="ja">${esc(day.description_ja)}</textarea>
          </div>
          <div class="field">
            <label for="f-description_en">English <span class="ja">英文</span></label>
            <textarea class="control" id="f-description_en" data-key="description_en">${esc(day.description_en)}</textarea>
          </div>
        </div>

        <h2 class="sec-title">image · ${day.candidates.length} candidate${day.candidates.length === 1 ? "" : "s"}</h2>
        <div class="gallery">${renderCandidates(day)}</div>
      </div>
    </article>

    <div class="actionbar">
      <label class="toggle">
        <input type="checkbox" id="approved" ${day.approved ? "checked" : ""}>
        <span class="toggle__track"></span>
        <span class="toggle__label">${day.approved ? "approved" : "approve"}</span>
      </label>
      <span class="msg" id="msg"></span>
      <button class="btn-save" id="save">save <kbd>⌘S</kbd></button>
    </div>`;

  wireEditor(day.date);
}

function renderCandidates(day) {
  if (!day.candidates.length)
    return `<p class="gallery__empty">No candidates yet — run <code>fill.py generate</code> for this date.</p>`;
  return day.candidates.map((c) => {
    const ref = (c.usable || "").toLowerCase() === "no";
    const chosen = day.chosen_candidate_id === c.id;
    return `
      <label class="cand ${chosen ? "is-chosen" : ""} ${ref ? "is-ref" : ""}"
             data-cand="${c.id}">
        <input type="radio" name="chosen" value="${c.id}"
               ${chosen ? "checked" : ""} ${ref ? "disabled" : ""}>
        <img class="cand__img" src="/candidates/${esc(c.out_file)}" alt="" loading="lazy">
        ${ref ? `<span class="cand__ref">reference only</span>`
              : `<span class="cand__badge">✓</span>`}
        <span class="cand__meta">
          <b>${esc(c.photographer) || "unknown"}</b><br>
          ${esc(c.provider)}${c.search_lang ? " · " + esc(c.search_lang) : ""}
        </span>
        ${c.source_url ? `<a class="cand__src" href="${esc(c.source_url)}"
             target="_blank" rel="noopener noreferrer"
             onclick="event.stopPropagation()">original source ↗</a>` : ""}
      </label>`;
  }).join("");
}

/* --------------------------------------------------------------- wiring/io */
function autosize(el) {
  el.style.height = "auto";
  el.style.height = el.scrollHeight + 2 + "px";
}

function wireEditor(date) {
  const markDirty = () => setDirty(true);
  for (const el of document.querySelectorAll("#editor [data-key]"))
    el.addEventListener("input", markDirty);
  for (const ta of document.querySelectorAll("#editor textarea")) {
    autosize(ta);                                   // fit initial content
    ta.addEventListener("input", () => autosize(ta));
  }
  for (const el of document.querySelectorAll('input[name="chosen"]'))
    el.addEventListener("change", () => {
      for (const c of document.querySelectorAll(".cand"))
        c.classList.toggle("is-chosen", c.querySelector("input").checked);
      markDirty();
    });
  $("#approved").addEventListener("change", (e) => {
    $(".toggle__label").textContent = e.target.checked ? "approved" : "approve";
    markDirty();
  });
  $("#save").onclick = () => saveEditor(date);
}

function setDirty(v) {
  state.dirty = v;
  const btn = $("#save");
  if (btn) btn.classList.toggle("is-dirty", v);
  const msg = $("#msg");
  if (v && msg) { msg.textContent = ""; msg.className = "msg"; }
}

async function saveEditor(date) {
  const body = {};
  for (const el of document.querySelectorAll("#editor [data-key]"))
    body[el.dataset.key] = el.value;
  const chosen = document.querySelector('input[name="chosen"]:checked');
  if (chosen) body.chosen_candidate_id = Number(chosen.value);
  body.approved = $("#approved").checked;

  const msg = $("#msg");
  msg.textContent = "saving…"; msg.className = "msg";
  const res = await fetch("/api/days/" + date, {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (res.ok) {
    msg.textContent = "✓ saved"; msg.className = "msg ok";
    setDirty(false);
    await loadDays();
    setTimeout(() => { if (msg.textContent === "✓ saved") { msg.style.opacity = "0"; } }, 2200);
    msg.style.opacity = "1";
  } else {
    msg.textContent = "✕ " + (await res.text()); msg.className = "msg err";
  }
}

/* --------------------------------------------------------------- controls */
$("#statusSeg").addEventListener("click", (e) => {
  const btn = e.target.closest(".seg");
  if (!btn) return;
  for (const b of document.querySelectorAll(".seg")) b.classList.remove("is-active");
  btn.classList.add("is-active");
  state.status = btn.dataset.status;
  loadDays();
});
for (const id of ["#from", "#to"])
  $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") loadDays(); });

document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
    e.preventDefault();
    if (state.selected && $("#save")) saveEditor(state.selected);
  }
});

loadDays();
