(() => {
  const header = document.querySelector(".site-header");
  const nav = header && header.querySelector(".site-nav");
  if (header && nav) {
    nav.id = nav.id || "site-nav";
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "nav-toggle";
    toggle.setAttribute("aria-controls", nav.id);
    toggle.setAttribute("aria-expanded", "false");
    toggle.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">' +
      '<path class="bar-top" d="M4 7h16"/><path class="bar-mid" d="M4 12h16"/><path class="bar-bot" d="M4 17h16"/></svg>' +
      '<span class="nav-toggle-label">Menu</span>';
    nav.before(toggle);

    const setOpen = (open) => {
      header.classList.toggle("nav-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    };
    setOpen(false);
    toggle.addEventListener("click", () => setOpen(!header.classList.contains("nav-open")));
    nav.addEventListener("click", (event) => {
      if (event.target instanceof Element && event.target.closest("a")) { setOpen(false); }
    });
    document.addEventListener("click", (event) => {
      if (header.classList.contains("nav-open") && event.target instanceof Node && !header.contains(event.target)) {
        setOpen(false);
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && header.classList.contains("nav-open")) {
        setOpen(false);
        toggle.focus();
      }
    });
    window.matchMedia("(min-width: 1101px)").addEventListener("change", (event) => {
      if (event.matches) { setOpen(false); }
    });
  }

  if (navigator.clipboard) {
    document.querySelectorAll(".content-section pre").forEach((pre) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "copy-button";
      button.textContent = "Copy";
      button.setAttribute("aria-label", "Copy code to clipboard");
      button.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(pre.innerText.trim());
          button.textContent = "Copied";
        } catch {
          button.textContent = "Copy failed";
        }
        setTimeout(() => { button.textContent = "Copy"; }, 2000);
      });
      const wrapper = document.createElement("div");
      wrapper.className = "code-block";
      pre.replaceWith(wrapper);
      wrapper.append(pre, button);
    });
  }
})();
