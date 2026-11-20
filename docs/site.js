"use strict";

const agent = document.querySelector("#agent");
const config = document.querySelector("#config");
const cliNote = document.querySelector("#cli-note code");
const copy = document.querySelector("#copy");
const status = document.querySelector("#copy-status");
const template = config.textContent;
const commands = { codex: "codex", agy: "agy", cursor: "agent" };

agent.addEventListener("change", () => {
  const selected = Object.hasOwn(commands, agent.value) ? agent.value : "codex";
  config.textContent = template.replace('agent = "codex"', `agent = "${selected}"`);
  cliNote.textContent = commands[selected];
  status.textContent = "";
});

copy.hidden = false;
copy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(config.textContent);
    status.textContent = "Configuration copied.";
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(config);
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = "Select and copy the configuration with your keyboard or context menu.";
  }
});
