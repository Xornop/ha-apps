const container = document.getElementById("groups-container");
const optimisticStates = new Map();

// Skip refreshing while the user is holding a slider
let interacting = false;

// Bitmask of HA media_player supported_features
const MP = {
  PAUSE: 1,
  VOLUME_SET: 4,
  PREVIOUS_TRACK: 16,
  NEXT_TRACK: 32,
  TURN_ON: 128,
  TURN_OFF: 256,
  VOLUME_STEP: 1024,
  PLAY: 16384,
};

function domainOf(entityId) {
  return entityId.split(".")[0];
}

function setOptimisticState(entityId, stateData, timeoutMs = 2000) {
  const expiry = Date.now() + timeoutMs;
  optimisticStates.set(entityId, { data: stateData, expiry });
}

function callService(entityId, service, data = {}, optimisticUpdate = {}) {
  if (Object.keys(optimisticUpdate).length > 0) {
    setOptimisticState(entityId, optimisticUpdate);
    refresh();
  }

  return fetch("/api/service", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      entity_id: entityId,
      service,
      data,
    }),
  })
    .then(() => {
      setTimeout(refresh, 300);
    })
    .catch((err) => {
      console.error("Error calling service:", err);
      optimisticStates.delete(entityId);
      refresh();
    });
}

function createButton(label, onClick, active = false) {
  const btn = document.createElement("button");
  btn.textContent = label;
  btn.className = active ? "active" : "";
  btn.onclick = onClick;
  return btn;
}

// Icon-only button without active color; briefly shows a "pressed" look
function createIconButton(icon, label, onClick) {
  const btn = document.createElement("button");
  btn.textContent = icon + "\uFE0E";
  btn.title = label;
  btn.setAttribute("aria-label", label);
  btn.className = "icon-btn";
  btn.onclick = () => {
    btn.classList.add("pressed");
    setTimeout(() => btn.classList.remove("pressed"), 200);
    onClick();
  };
  return btn;
}

// Prevents refresh() from replacing the slider while dragging
function attachSliderGuard(slider) {
  const start = () => {
    interacting = true;
  };
  const end = () => {
    interacting = false;
  };
  slider.addEventListener("pointerdown", start);
  slider.addEventListener("pointerup", end);
  slider.addEventListener("pointercancel", end);
  slider.addEventListener("change", end);
}

function renderLightControls(entity, card) {
  const row = document.createElement("div");
  row.className = "row";

  const isOn = entity.state === "on";

  const powerButton = createButton(
    isOn ? "Off" : "On",
    () =>
      callService(
        entity.entity_id,
        isOn ? "turn_off" : "turn_on",
        {},
        { state: isOn ? "off" : "on" }
      ),
    isOn
  );

  row.appendChild(powerButton);
  card.appendChild(row);

  // Brightness
  const brightnessSection = document.createElement("div");
  brightnessSection.className = "light-control";

  const brightnessHeader = document.createElement("div");
  brightnessHeader.className = "control-header";

  const brightnessLabel = document.createElement("span");
  brightnessLabel.textContent = "Brightness";

  const brightnessValue = document.createElement("span");
  brightnessValue.className = "control-value";

  const currentBrightness =
    entity.brightness != null
      ? Math.round((entity.brightness / 255) * 100)
      : 100;

  brightnessValue.textContent = `${currentBrightness}%`;

  brightnessHeader.appendChild(brightnessLabel);
  brightnessHeader.appendChild(brightnessValue);
  brightnessSection.appendChild(brightnessHeader);

  const slider = document.createElement("input");
  slider.type = "range";
  slider.min = "1";
  slider.max = "100";
  slider.value = String(currentBrightness);
  slider.className = "brightness-slider";
  attachSliderGuard(slider);

  let brightnessTimeout;

  slider.addEventListener("input", () => {
    brightnessValue.textContent = `${slider.value}%`;
  });

  slider.addEventListener("change", () => {
    clearTimeout(brightnessTimeout);

    const targetPct = Number(slider.value);
    const targetBrightnessValue = Math.round((targetPct / 100) * 255);

    brightnessTimeout = setTimeout(() => {
      callService(
        entity.entity_id,
        "turn_on",
        { brightness_pct: targetPct },
        { state: "on", brightness: targetBrightnessValue }
      );
    }, 50);
  });

  brightnessSection.appendChild(slider);
  card.appendChild(brightnessSection);

  // Color temperature
  const supportedModes = entity.supported_color_modes || [];
  const supportsColorTemperature = supportedModes.includes("color_temp");

  if (supportsColorTemperature) {
    const colorSection = document.createElement("div");
    colorSection.className = "light-control";

    const colorLabel = document.createElement("div");
    colorLabel.className = "control-label";
    colorLabel.textContent = "White tone";

    colorSection.appendChild(colorLabel);

    const colorRow = document.createElement("div");
    colorRow.className = "row";

    const warmButton = createButton(
      "Warm white",
      () => callService(entity.entity_id, "turn_on", { color_temp_kelvin: 2000 }, { state: "on" })
    );

    const coldButton = createButton(
      "Cool white",
      () => callService(entity.entity_id, "turn_on", { color_temp_kelvin: 4000 }, { state: "on" })
    );

    colorRow.appendChild(warmButton);
    colorRow.appendChild(coldButton);
    colorSection.appendChild(colorRow);
    card.appendChild(colorSection);
  }
}

function renderMediaPlayerControls(entity, card) {
  const features = Number(entity.supported_features) || 0;
  const supports = (bit) => (features & bit) !== 0;

  const isUnavailable = entity.state === "unavailable";
  const isOff = entity.state === "off";

  // Current track
  if (!isOff && !isUnavailable && (entity.media_title || entity.media_artist)) {
    const info = document.createElement("div");
    info.className = "state media-info";
    info.textContent = [entity.media_artist, entity.media_title]
      .filter(Boolean)
      .join(" — ");
    card.appendChild(info);
  }

  if (isUnavailable) {
    const state = document.createElement("div");
    state.className = "state";
    state.textContent = "Unavailable";
    card.appendChild(state);
    return;
  }

  // Power
  if (supports(MP.TURN_ON) || supports(MP.TURN_OFF)) {
    const powerRow = document.createElement("div");
    powerRow.className = "row";
    powerRow.appendChild(
      createButton(
        isOff ? "On" : "Off",
        () =>
          callService(
            entity.entity_id,
            isOff ? "turn_on" : "turn_off",
            {},
            { state: isOff ? "idle" : "off" }
          ),
        !isOff
      )
    );
    card.appendChild(powerRow);
  }

  if (isOff) return;

  // Previous / play-pause / next
  const transportRow = document.createElement("div");
  transportRow.className = "row";

  if (supports(MP.PREVIOUS_TRACK)) {
    transportRow.appendChild(
      createIconButton("⏮", "Previous", () =>
        callService(entity.entity_id, "media_previous_track")
      )
    );
  }

  if (supports(MP.PAUSE) || supports(MP.PLAY)) {
    transportRow.appendChild(
      createIconButton("⏯", "Play/pause", () =>
        callService(entity.entity_id, "media_play_pause")
      )
    );
  }

  if (supports(MP.NEXT_TRACK)) {
    transportRow.appendChild(
      createIconButton("⏭", "Next", () =>
        callService(entity.entity_id, "media_next_track")
      )
    );
  }

  if (transportRow.children.length > 0) {
    card.appendChild(transportRow);
  }

  // Volume down/up (visible as long as the player is on)
  if (supports(MP.VOLUME_STEP) || supports(MP.VOLUME_SET)) {
    const volumeRow = document.createElement("div");
    volumeRow.className = "row";

    volumeRow.appendChild(
      createIconButton("🔉", "Volume down", () =>
        callService(entity.entity_id, "volume_down")
      )
    );
    volumeRow.appendChild(
      createIconButton("🔊", "Volume up", () =>
        callService(entity.entity_id, "volume_up")
      )
    );

    card.appendChild(volumeRow);
  }
}

function renderCard(entity, isMain = false) {
  const domain = domainOf(entity.entity_id);
  const card = document.createElement("div");
  card.className = isMain ? "card main-card" : "card";

  const name = document.createElement("div");
  name.className = "name";
  name.textContent = isMain ? `⭐ ${entity.friendly_name}` : entity.friendly_name;

  card.appendChild(name);

  if (domain === "light") {
    renderLightControls(entity, card);
  } else if (domain === "media_player") {
    renderMediaPlayerControls(entity, card);
  } else if (["switch", "input_boolean", "fan"].includes(domain)) {
    const row = document.createElement("div");
    row.className = "row";
    const isOn = entity.state === "on";

    const btn = createButton(
      isOn ? "Off" : "On",
      () => callService(entity.entity_id, isOn ? "turn_off" : "turn_on", {}, { state: isOn ? "off" : "on" }),
      isOn
    );

    row.appendChild(btn);
    card.appendChild(row);
  } else if (domain === "cover") {
    const row = document.createElement("div");
    row.className = "row";

    [
      ["open_cover", "Open", "open"],
      ["stop_cover", "Stop", "opening"],
      ["close_cover", "Close", "closed"],
    ].forEach(([service, label, targetState]) => {
      const btn = createButton(
        label,
        () => callService(entity.entity_id, service, {}, { state: targetState })
      );
      row.appendChild(btn);
    });

    card.appendChild(row);
  } else if (domain === "lock") {
    const row = document.createElement("div");
    row.className = "row";
    const isLocked = entity.state === "locked";

    const btn = createButton(
      isLocked ? "Unlock" : "Lock",
      () => callService(entity.entity_id, isLocked ? "unlock" : "lock", {}, { state: isLocked ? "unlocked" : "locked" }),
      isLocked
    );

    row.appendChild(btn);
    card.appendChild(row);
  } else {
    const state = document.createElement("div");
    state.className = "state";
    state.textContent = entity.unit_of_measurement
      ? `${entity.state} ${entity.unit_of_measurement}`
      : entity.state;
    card.appendChild(state);
  }

  return card;
}

function refresh() {
  if (interacting) return;

  fetch("/api/states")
    .then((r) => r.json())
    .then((groups) => {
      // The user may have started holding a slider while fetching
      if (interacting) return;

      container.innerHTML = "";

      groups.forEach((group) => {
        const groupSection = document.createElement("section");
        groupSection.className = "group-section";

        const groupTitle = document.createElement("h2");
        groupTitle.className = "group-title";
        groupTitle.textContent = group.name;
        groupSection.appendChild(groupTitle);

        const cardsGrid = document.createElement("div");
        cardsGrid.className = "grid";

        // Render main entity if present
        if (group.main_entity) {
          let mainEntity = group.main_entity;
          const cachedMain = optimisticStates.get(mainEntity.entity_id);
          if (cachedMain) {
            if (Date.now() < cachedMain.expiry) {
              mainEntity = { ...mainEntity, ...cachedMain.data };
            } else {
              optimisticStates.delete(mainEntity.entity_id);
            }
          }
          cardsGrid.appendChild(renderCard(mainEntity, true));
        }

        // Render all other entities in the group
        if (Array.isArray(group.entities)) {
          group.entities.forEach((entity) => {
            const cached = optimisticStates.get(entity.entity_id);
            if (cached) {
              if (Date.now() < cached.expiry) {
                entity = { ...entity, ...cached.data };
              } else {
                optimisticStates.delete(entity.entity_id);
              }
            }
            cardsGrid.appendChild(renderCard(entity, false));
          });
        }

        groupSection.appendChild(cardsGrid);
        container.appendChild(groupSection);
      });
    })
    .catch((err) => {
      console.error("Could not fetch groups:", err);
    });
}

refresh();
setInterval(refresh, 5000);
