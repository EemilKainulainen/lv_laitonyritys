// html/script.js

// ==========================
// ROOT & COMMON ELEMENTS
// ==========================

const app = document.getElementById("app");

// BROWSER ELEMENTS
const browserShell = document.getElementById("browser-shell");
const playerNameEl = document.getElementById("player-name");
const cashEl = document.getElementById("cash-value");
const bankEl = document.getElementById("bank-value");
const categoryListEl = document.getElementById("category-list");
const gridEl = document.getElementById("business-grid");
const gridTitleEl = document.getElementById("grid-title");
const tabButtons = document.querySelectorAll(".tab-btn");

// FACILITY HUD ELEMENTS
const hudEl = document.getElementById("facility-hud");
const hudValueEl = document.getElementById("hud-value");
const hudProdPctEl = document.getElementById("hud-prod-pct");
const hudSupPctEl = document.getElementById("hud-sup-pct");

const permModalEl = document.getElementById("permissions-modal");
const permNameEl = document.getElementById("perm-player-name");

const permStashEl   = document.getElementById("perm-stash");
const permSellEl    = document.getElementById("perm-sell");
const permBuyEl     = document.getElementById("perm-buy");
const permStealEl   = document.getElementById("perm-steal");
const permUpgradeEl = document.getElementById("perm-upgrade");

let currentPermTarget = null;
let currentPermEntry  = null;

// NEW LAPTOP ROOT
const laptopRoot = document.getElementById("laptop-root");

// ==========================
// NUI HELPER
// ==========================

const NUI_RESOURCE = "lv_laitonyritys";

function fetchNui(action, data = {}) {
  return fetch(`https://${NUI_RESOURCE}/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(data),
  }).catch(() => {});
}

// ==========================
// COMMON HELPERS
// ==========================

function setAppVisible(v) {
  if (!app) return;
  if (v) {
    app.classList.remove("hidden");
    requestAnimationFrame(() => app.classList.add("visible"));
  } else {
    app.classList.remove("visible");
    setTimeout(() => app.classList.add("hidden"), 150);
  }
}

function formatMoney(amount) {
  amount = Number(amount) || 0;
  return "$ " + amount.toLocaleString("en-US");
}

function openPermModal(identifier, entry) {
  if (!permModalEl) return;
  currentPermTarget = identifier;
  currentPermEntry  = entry;

  if (permNameEl) {
    permNameEl.textContent = `For: ${entry.name || identifier}`;
  }

  // default true if undefined
  permStashEl.checked   = entry.can_stash   !== false;
  permSellEl.checked    = entry.can_sell    !== false;
  permBuyEl.checked     = entry.can_buy     !== false;
  permStealEl.checked   = entry.can_steal   !== false;
  permUpgradeEl.checked = entry.can_upgrade !== false;

  permModalEl.classList.remove("hidden");
}

function closePermModal() {
  if (!permModalEl) return;
  currentPermTarget = null;
  currentPermEntry  = null;
  permModalEl.classList.add("hidden");
}

// ==========================
// GLOBAL STATE
// ==========================

const state = {
  mode: null, // 'browser' | 'laptop'
  open: false,

  // browser
  browserTab: "buy",
  browserCategory: "all",
  browserBusinesses: [],

  // laptop (new UI)
  laptopBusinessId: null,
  laptopData: null,
  laptopOpen: false,
  laptopResupplyActive: false,
  laptopSellActive: false,
};

// ==========================
// FACILITY HUD
// ==========================

function updateFacilityHud(data) {
  if (!data) return;
  const prod = data.product || 0;
  const maxProd = data.maxProduct || 1;
  const sup = data.supplies || 0;
  const maxSup = data.maxSupplies || 1;
  const unit = data.productSellPrice || 0;

  const totalValue = prod * unit;
  if (hudValueEl) hudValueEl.textContent = formatMoney(totalValue);

  const prodPct = Math.min(100, Math.round((prod / maxProd) * 100));
  const supPct = Math.min(100, Math.round((sup / maxSup) * 100));

  if (hudProdPctEl) hudProdPctEl.textContent = prodPct + "%";
  if (hudSupPctEl) hudSupPctEl.textContent = supPct + "%";
}

// ==========================
// BROWSER MODE
// ==========================

function buildCategoryCounts() {
  const counts = {
    all: 0,
    meth: 0,
    coke: 0,
    weed: 0,
    counterfeit: 0,
    forgery: 0,
  };

  state.browserBusinesses.forEach((biz) => {
    counts.all++;
    const t = (biz.type || "").toLowerCase();
    if (counts[t] !== undefined) counts[t]++;
  });

  return counts;
}

function renderCategories() {
  if (!categoryListEl) return;

  const counts = buildCategoryCounts();
  const items = [
    { id: "all", label: "Show All" },
    { id: "meth", label: "Meth" },
    { id: "coke", label: "Coke" },
    { id: "weed", label: "Weed" },
    { id: "counterfeit", label: "Counterfeit Factory" },
    { id: "forgery", label: "Document Forgery" },
  ];

  categoryListEl.innerHTML = "";
  items.forEach((item) => {
    const btn = document.createElement("button");
    btn.className =
      "category-item" +
      (state.browserCategory === item.id ? " active" : "");
    btn.dataset.category = item.id;
    btn.innerHTML = `
      <span>${item.label}</span>
      <span class="count">(${counts[item.id] || 0})</span>
    `;
    btn.addEventListener("click", () => {
      state.browserCategory = item.id;
      renderCategories();
      renderGrid();
    });
    categoryListEl.appendChild(btn);
  });
}

function filteredBusinesses() {
  return state.browserBusinesses.filter((biz) => {
    if (state.browserTab === "buy" && biz.owned) return false;
    if (state.browserTab === "owned" && !biz.isOwner) return false;

    if (state.browserCategory === "all") return true;
    return (biz.type || "").toLowerCase() === state.browserCategory;
  });
}

function renderGrid() {
  if (!gridEl || !gridTitleEl) return;

  const list = filteredBusinesses();
  gridEl.innerHTML = "";

  if (state.browserTab === "buy") {
    gridTitleEl.textContent = "Available Businesses";
  } else {
    gridTitleEl.textContent = "Your Businesses";
  }

  if (!list.length) {
    const empty = document.createElement("div");
    empty.style.padding = "12px";
    empty.style.color = "#9ca3af";
    empty.style.fontSize = ".85rem";
    empty.textContent = "No businesses found for this filter.";
    gridEl.appendChild(empty);
    return;
  }

  list.forEach((biz) => {
    const card = document.createElement("div");
    card.className = "business-card";

    const price = biz.price || 0;
    const area = biz.area || "Unknown";
    const imgUrl = biz.image || "";

    card.innerHTML = `
      <div class="card-top-row">
        <div>
          <span class="label">Starting At:</span>
          <span class="value">${formatMoney(price)}</span>
        </div>
        <div style="text-align:right;">
          <span class="label">Location:</span>
          <span class="value">${area}</span>
        </div>
      </div>

      <div class="card-buttons">
        <button class="btn primary btn-purchase">${
          biz.owned ? "Owned" : "Purchase"
        }</button>
        <button class="btn secondary btn-gps">Mark on GPS</button>
      </div>

      <div class="biz-img" ${
        imgUrl
          ? `style="background-image: linear-gradient(135deg, rgba(15,23,42,.5), rgba(15,23,42,.5)), url('${imgUrl}');"`
          : ""
      }></div>

      <div class="biz-title">${biz.label}</div>
      <div class="biz-desc">
        ${biz.description || biz.typeLabel || ""}
      </div>
    `;

    const purchaseBtn = card.querySelector(".btn-purchase");
    const gpsBtn = card.querySelector(".btn-gps");

    if (biz.owned && !biz.isOwner && state.browserTab === "buy") {
      purchaseBtn.textContent = "Unavailable";
      purchaseBtn.classList.add("disabled");
    } else if (biz.owned && state.browserTab === "owned") {
      purchaseBtn.textContent = "Owned";
      purchaseBtn.classList.add("disabled");
    } else if (biz.owned && state.browserTab === "buy") {
      purchaseBtn.textContent = "Owned (You)";
      purchaseBtn.classList.add("disabled");
    } else {
      purchaseBtn.addEventListener("click", () => {
        fetchNui("purchaseBusiness", { businessId: biz.businessId });
      });
    }

    gpsBtn.addEventListener("click", () => {
      fetchNui("markGps", { businessId: biz.businessId });
    });

    gridEl.appendChild(card);
  });
}

function setBrowserTab(tab) {
  state.browserTab = tab;
  tabButtons.forEach((btn) =>
    btn.classList.toggle("active", btn.dataset.tab === tab)
  );
  renderGrid();
}

tabButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    setBrowserTab(btn.dataset.tab);
  });
});

// ==========================
// NEW LAPTOP UI
// ==========================

function setLaptopVisible(open) {
  state.laptopOpen = open;
  if (!laptopRoot) return;
  laptopRoot.classList.toggle("hidden", !open);
}

function clampPercent(num) {
  if (!num || isNaN(num)) return 0;
  if (num < 0) return 0;
  if (num > 100) return 100;
  return Math.round(num);
}

function renderLaptop() {
  if (!state.laptopData || !laptopRoot) return;

  const d = state.laptopData;

  // Player name (optional nice touch)
  const playerNameLap = document.getElementById("laptop-player-name");
  if (playerNameLap && d.ownerName) {
    playerNameLap.textContent = d.ownerName;
  }

  // Facility info
  const nameEl = document.getElementById("laptop-facility-name");
  if (nameEl) nameEl.textContent = d.locationLabel || "Business";

  const imgEl = document.getElementById("laptop-facility-image");
  if (imgEl) {
    if (d.image) imgEl.src = d.image;
    else imgEl.src = "images/placeholder.png";
  }

  // Products
  const productsPercent =
    d.maxProduct && d.maxProduct > 0
      ? clampPercent((d.product / d.maxProduct) * 100)
      : 0;

  const productsPercentEl = document.getElementById("laptop-products-percent");
  const productsBarEl = document.getElementById("laptop-products-bar");
  if (productsPercentEl) productsPercentEl.textContent = productsPercent + "%";
  if (productsBarEl) productsBarEl.style.width = productsPercent + "%";

  const worth = (d.product || 0) * (d.productSellPrice || 0);
  const worthEl = document.getElementById("laptop-products-worth");
  if (worthEl) worthEl.textContent = formatMoney(worth);

  // Supplies
  const suppliesPercent =
    d.maxSupplies && d.maxSupplies > 0
      ? clampPercent((d.supplies / d.maxSupplies) * 100)
      : 0;
  const suppliesPercentEl = document.getElementById("laptop-supplies-percent");
  const suppliesBarEl = document.getElementById("laptop-supplies-bar");
  if (suppliesPercentEl) suppliesPercentEl.textContent = suppliesPercent + "%";
  if (suppliesBarEl) suppliesBarEl.style.width = suppliesPercent + "%";

  // Buy supplies cost (fill to 100%)
  const missingSupplies = Math.max(
    (d.maxSupplies || 0) - (d.supplies || 0),
    0
  );
  const buyCost = missingSupplies * (d.supplyUnitPrice || 0);
  const buyCostEl = document.getElementById("laptop-buy-cost");
  if (buyCostEl)
    buyCostEl.textContent = buyCost > 0 ? formatMoney(buyCost) : "";

  // Keys list
  const keysListEl = document.getElementById("keys-list");
  const keysEmptyEl = document.getElementById("keys-empty");
  if (keysListEl) {
    keysListEl.innerHTML = "";
    let hasAny = false;

    if (d.associates) {
      for (const [identifier, entry] of Object.entries(d.associates)) {
        hasAny = true;
        const row = document.createElement("div");
        row.className = "keys-row";

        const displayName = entry.name || identifier;

        // Name column
        const nameSpan = document.createElement("span");
        nameSpan.className = "keys-row-name";
        nameSpan.textContent = displayName;

        // Permissions column
        const permsSpan = document.createElement("span");
        permsSpan.className = "keys-row-perms";
        const permBtn = document.createElement("button");
        permBtn.className = "btn-perms";
        permBtn.textContent = "Permissions";
        permBtn.addEventListener("click", () => {
          openPermModal(identifier, entry);
        });
        permsSpan.appendChild(permBtn);

        // Access column
        const accessSpan = document.createElement("span");
        accessSpan.className = "keys-row-access";
        const revokeBtn = document.createElement("button");
        revokeBtn.className = "btn-revoke";
        revokeBtn.textContent = "Revoke";
        revokeBtn.addEventListener("click", () => {
          fetchNui("removeAssociate", { identifier });
        });
        accessSpan.appendChild(revokeBtn);

        row.appendChild(nameSpan);
        row.appendChild(permsSpan);
        row.appendChild(accessSpan);
        keysListEl.appendChild(row);
      }
    }

    if (keysEmptyEl) {
      keysEmptyEl.style.display = hasAny ? "none" : "block";
    }
  }

  // --- Upgrade LEVELS (new part) ---
  const levelEquipmentEl = document.getElementById("level-equipment");
  const levelEmployeesEl = document.getElementById("level-employees");
  const levelSecurityEl  = document.getElementById("level-security");

  if (levelEquipmentEl) {
    levelEquipmentEl.textContent = "Level " + (d.equipmentLevel || 0);
  }
  if (levelEmployeesEl) {
    levelEmployeesEl.textContent = "Level " + (d.employeesLevel || 0);
  }
  if (levelSecurityEl) {
    levelSecurityEl.textContent = "Level " + (d.securityLevel || 0);
  }

  // Upgrades prices
  const priceEquipmentEl = document.getElementById("price-equipment");
  const priceEmployeesEl = document.getElementById("price-employees");
  const priceSecurityEl = document.getElementById("price-security");

  function setPrice(el, value) {
    if (!el) return;
    if (!value || value <= 0) {
      el.textContent = "MAX LEVEL";
      el.style.opacity = 0.7;
    } else {
      el.textContent = formatMoney(value);
      el.style.opacity = 1;
    }
  }

  if (d.upgradePrices) {
    setPrice(priceEquipmentEl, d.upgradePrices.equipment);
    setPrice(priceEmployeesEl, d.upgradePrices.employees);
    setPrice(priceSecurityEl, d.upgradePrices.security);
  }

  // --- Buttons: Sell / Steal / Buy: reactive state ---

  // Sell Products button
  const sellBtn = document.getElementById("btn-sell-products");
  if (sellBtn) {
    const minProduct = Math.floor((d.maxProduct || 0) * 0.25);
    const canSell =
      (d.product || 0) >= minProduct && !d.isShutDown && !!d.owned;
    const active = state.laptopSellActive;

    sellBtn.disabled = !canSell || active;
    sellBtn.classList.toggle("disabled", sellBtn.disabled);
    sellBtn.textContent = active ? "Sell Mission Active" : "Sell Products";
  }

  // Steal Supplies button (resupply mission)
  const stealBtn = document.getElementById("btn-steal-supplies");
  if (stealBtn) {
    const active = state.laptopResupplyActive;
    stealBtn.disabled = active;
    stealBtn.classList.toggle("disabled", stealBtn.disabled);
    stealBtn.textContent = active ? "Resupply Mission Active" : "Steal Supplies";
  }

  // Buy Supplies button
  const buyBtn = document.getElementById("btn-buy-supplies");
  if (buyBtn) {
    const canBuy = missingSupplies > 0 && !state.laptopResupplyActive;
    buyBtn.disabled = !canBuy;
    buyBtn.classList.toggle("disabled", buyBtn.disabled);

    if (missingSupplies <= 0) {
      buyBtn.textContent = "Supplies Full";
      if (buyCostEl) buyCostEl.textContent = "";
    } else {
      buyBtn.textContent = "Buy Supplies";
    }
  }

  // Upgrade buttons: disable when at max level
  function handleUpgradeButton(typeKey, priceValue) {
    const btn = document.querySelector(
      '.btn-upgrade[data-upgrade="' + typeKey + '"]'
    );
    if (!btn) return;
    const disabled = !priceValue || priceValue <= 0;
    btn.disabled = disabled;
    btn.classList.toggle("disabled", disabled);
  }

  if (d.upgradePrices) {
    handleUpgradeButton("equipment", d.upgradePrices.equipment);
    handleUpgradeButton("employees", d.upgradePrices.employees);
    handleUpgradeButton("security", d.upgradePrices.security);
  }
}


// ==========================
// NEW LAPTOP BUTTON HANDLERS
// ==========================

function hookLaptopButtons() {
  const closeBtn = document.getElementById("laptop-close-btn");
  if (closeBtn) {
    closeBtn.addEventListener("click", () => {
      fetchNui("close", {});
    });
  }

  // Sell products
  const sellBtn = document.getElementById("btn-sell-products");
  if (sellBtn) {
    sellBtn.addEventListener("click", () => {
      if (!state.laptopBusinessId) return;
      if (state.laptopSellActive || sellBtn.disabled) return;
      fetchNui("startSell", { missionType: 1 });
    });
  }

  // Buy supplies (fill to full)
  const buyBtn = document.getElementById("btn-buy-supplies");
  if (buyBtn) {
    buyBtn.addEventListener("click", () => {
      if (!state.laptopData) return;
      if (buyBtn.disabled) return;

      const missing = Math.max(
        (state.laptopData.maxSupplies || 0) -
          (state.laptopData.supplies || 0),
        0
      );
      if (missing <= 0) return;
      fetchNui("buySupplies", { amount: missing });
    });
  }

  // Steal supplies (resupply mission)
  const stealBtn = document.getElementById("btn-steal-supplies");
  if (stealBtn) {
    stealBtn.addEventListener("click", () => {
      if (state.laptopResupplyActive || stealBtn.disabled) return;
      fetchNui("startResupply", { missionType: 1 });
    });
  }

  // Give keys
  const giveInput = document.getElementById("input-give-keys");
  const giveBtn = document.getElementById("btn-give-keys");
  if (giveBtn && giveInput) {
    giveBtn.addEventListener("click", () => {
      const val = giveInput.value.trim();
      if (!val) return;
      fetchNui("addAssociate", { identifier: val });
      giveInput.value = "";
    });
  }

  // Permissions modal
  const permCancel = document.getElementById("perm-cancel");
  const permApply = document.getElementById("perm-apply");

  if (permCancel) {
    permCancel.addEventListener("click", () => {
      closePermModal();
    });
  }

  if (permApply) {
    permApply.addEventListener("click", () => {
      if (!currentPermTarget) return;
      const payload = {
        identifier: currentPermTarget,
        can_stash: permStashEl.checked,
        can_sell: permSellEl.checked,
        can_buy: permBuyEl.checked,
        can_steal: permStealEl.checked,
        can_upgrade: permUpgradeEl.checked,
      };
      fetchNui("setPermissions", payload);
      closePermModal();
    });
  }

  // Transfer ownership
  const transferInput = document.getElementById("input-transfer");
  const transferBtn = document.getElementById("btn-transfer");
  if (transferBtn && transferInput) {
    transferBtn.addEventListener("click", () => {
      const val = transferInput.value.trim();
      if (!val) return;
      fetchNui("transfer", { targetServerId: val });
      transferInput.value = "";
    });
  }

  // Upgrades
  document.querySelectorAll(".btn-upgrade").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (btn.disabled) return;
      const type = btn.getAttribute("data-upgrade");
      if (!type) return;
      fetchNui("upgrade", { upgradeType: type });
    });
  });
}

// Call once on DOM ready
document.addEventListener("DOMContentLoaded", hookLaptopButtons);

// ==========================
// MESSAGE HANDLER (MERGED)
// ==========================

window.addEventListener("message", (e) => {
  const msg = e.data;
  if (!msg || !msg.action) return;

  if (msg.action === "openBusinessBrowser") {
    state.mode = "browser";
    state.open = true;

    if (browserShell) browserShell.classList.remove("hidden");
    setLaptopVisible(false);

    state.browserTab = "buy";
    state.browserCategory = "all";
    state.browserBusinesses = msg.businesses || [];

    if (playerNameEl) playerNameEl.textContent = msg.playerName || "Player";
    if (cashEl) cashEl.textContent = formatMoney(msg.cash || 0);
    if (bankEl) bankEl.textContent = formatMoney(msg.bank || 0);

    renderCategories();
    setBrowserTab("buy");
    setAppVisible(true);
  } else if (msg.action === "openLaptop") {
    state.mode = "laptop";
    state.open = true;

    if (browserShell) browserShell.classList.add("hidden");

    state.laptopBusinessId = msg.businessId;
    state.laptopData = msg.data || null;
    state.laptopResupplyActive = false;
    state.laptopSellActive = false;

    setLaptopVisible(true);
    renderLaptop();
    setAppVisible(true);
  } else if (msg.action === "update") {
    // generic business data update for laptop
    if (state.mode === "laptop" && msg.data) {
      state.laptopData = msg.data;
      renderLaptop();
    }
  } else if (msg.action === "updateBusinesses") {
    // Refresh browser data after purchase
    state.browserBusinesses = msg.businesses || state.browserBusinesses;
    if (msg.cash !== undefined && cashEl)
      cashEl.textContent = formatMoney(msg.cash);
    if (msg.bank !== undefined && bankEl)
      bankEl.textContent = formatMoney(msg.bank);
    renderCategories();
    renderGrid();
  } else if (msg.action === "showFacilityHud") {
    updateFacilityHud(msg.data);
    if (hudEl) hudEl.classList.remove("hidden");
  } else if (msg.action === "updateFacilityHud") {
    updateFacilityHud(msg.data);
  } else if (msg.action === "hideFacilityHud") {
    if (hudEl) hudEl.classList.add("hidden");
  } else if (msg.action === "closeLaptop") {
    state.open = false;
    setLaptopVisible(false);
    setAppVisible(false);
  } else if (msg.action === "resupplyStarted") {
    state.laptopResupplyActive = true;
    renderLaptop();
  } else if (msg.action === "sellStarted") {
    state.laptopSellActive = true;
    renderLaptop();
  } else if (msg.action === "close") {
    state.open = false;
    setLaptopVisible(false);
    setAppVisible(false);
  }
});

// ==========================
// ESC TO CLOSE (GLOBAL)
// ==========================

document.addEventListener("keydown", (e) => {
  if (
    (e.key === "Escape" || e.key === "Esc" || e.keyCode === 27) &&
    state.open
  ) {
    fetchNui("close", {});
  }
});