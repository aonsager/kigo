const $ = (sel) => document.querySelector(sel);

async function loadDays() {
  const params = new URLSearchParams();
  if ($("#from").value) params.set("from", $("#from").value);
  if ($("#to").value) params.set("to", $("#to").value);
  if ($("#status").value) params.set("status", $("#status").value);
  const days = await (await fetch("/api/days?" + params)).json();
  const ul = $("#days");
  ul.innerHTML = "";
  for (const d of days) {
    const li = document.createElement("li");
    if (d.approved) li.classList.add("approved");
    const marks = `${d.has_prose ? "✍" : "·"}${d.has_image ? "🖼" : "·"}${d.approved ? "✓" : ""}`;
    li.innerHTML = `<span>${d.date} ${d.kanji}</span><span class="marks">${marks}</span>`;
    li.onclick = () => loadEditor(d.date);
    ul.appendChild(li);
  }
}

async function loadEditor(date) {
  const day = await (await fetch("/api/days/" + date)).json();
  const ed = $("#editor");
  ed.hidden = false;
  const field = (label, key, tag = "input") =>
    `<label>${label}</label>${tag === "textarea"
      ? `<textarea data-key="${key}">${day[key] || ""}</textarea>`
      : `<input type="text" data-key="${key}" value="${(day[key] || "").replace(/"/g, "&quot;")}">`}`;
  const cands = day.candidates.map((c) => {
    const ref = (c.usable || "").toLowerCase() === "no";
    return `<figure class="${ref ? "refonly" : ""}">
      <label><input type="radio" name="chosen" value="${c.id}"
        ${day.chosen_candidate_id === c.id ? "checked" : ""} ${ref ? "disabled" : ""}>
      <img src="/candidates/${c.out_file}" alt=""></label>
      <figcaption>${c.provider} · ${c.photographer}${ref ? " · ref-only" : ""}</figcaption>
    </figure>`;
  }).join("");
  ed.innerHTML = `<h2>${day.date} ${day.kanji} (${day.reading_ja})</h2>
    ${field("reading_ja", "reading_ja")}
    ${field("reading_en", "reading_en")}
    ${field("translation_en", "translation_en")}
    ${field("description_ja", "description_ja", "textarea")}
    ${field("description_en", "description_en", "textarea")}
    <label>image candidates</label>
    <div class="candidates">${cands || "<em>none — run generate</em>"}</div>
    <div class="bar">
      <label><input type="checkbox" id="approved" ${day.approved ? "checked" : ""}> approved</label>
      <button id="save">save</button><span id="msg"></span>
    </div>`;
  $("#save").onclick = () => saveEditor(date);
}

async function saveEditor(date) {
  const body = {};
  for (const el of document.querySelectorAll("#editor [data-key]")) body[el.dataset.key] = el.value;
  const chosen = document.querySelector('input[name="chosen"]:checked');
  if (chosen) body.chosen_candidate_id = Number(chosen.value);
  body.approved = $("#approved").checked;
  const res = await fetch("/api/days/" + date, {
    method: "PATCH", headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  $("#msg").textContent = res.ok ? "saved" : "error: " + (await res.text());
  if (res.ok) loadDays();
}

$("#reload").onclick = loadDays;
loadDays();
