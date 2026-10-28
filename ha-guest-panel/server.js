const fs = require("fs");
const express = require("express");

const options = JSON.parse(fs.readFileSync("/data/options.json", "utf8"));

const HA_URL = "http://homeassistant:8123";
const HA_TOKEN = options.ha_token;
const GROUPS = options.groups || [];
const PORT = 8125;

if (!HA_TOKEN) {
  console.error("No ha_token set in the add-on configuration. Exiting.");
  process.exit(1);
}

// Collect all allowed entities from the groups (including main_entity)
const ALLOWED_ENTITIES = new Set();
GROUPS.forEach(group => {
  if (group.main_entity) {
    ALLOWED_ENTITIES.add(group.main_entity);
  }
  if (Array.isArray(group.entities)) {
    group.entities.forEach(e => ALLOWED_ENTITIES.add(e));
  }
});

if (ALLOWED_ENTITIES.size === 0) {
  console.warn("No groups or entities configured — the panel will show nothing.");
}

const ALLOWED_SERVICES = {
  light: ["turn_on", "turn_off", "toggle"],
  switch: ["turn_on", "turn_off", "toggle"],
  input_boolean: ["turn_on", "turn_off", "toggle"],
  cover: ["open_cover", "close_cover", "stop_cover"],
  fan: ["turn_on", "turn_off", "toggle"],
  lock: ["lock", "unlock"],
  media_player: [
    "turn_on",
    "turn_off",
    "media_play_pause",
    "media_previous_track",
    "media_next_track",
    "volume_up",
    "volume_down",
  ],
};

function domainOf(entityId) {
  return entityId.split(".")[0];
}

async function haFetch(path, init) {
  const res = await fetch(`${HA_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${HA_TOKEN}`,
      "Content-Type": "application/json",
      ...(init && init.headers),
    },
  });
  return res;
}

const app = express();

app.use(express.json());
app.use(express.static("public"));

// Helper to fetch entity data
async function fetchEntityState(entityId) {
  try {
    const r = await haFetch(`/api/states/${entityId}`);
    if (r.ok) {
      const data = await r.json();
      return {
        entity_id: data.entity_id,
        state: data.state,
        friendly_name: data.attributes.friendly_name || data.entity_id,
        unit_of_measurement: data.attributes.unit_of_measurement,
        device_class: data.attributes.device_class,
        brightness: data.attributes.brightness ?? null,
        color_temp_kelvin: data.attributes.color_temp_kelvin ?? null,
        supported_color_modes: data.attributes.supported_color_modes ?? [],
        // media_player
        supported_features: data.attributes.supported_features ?? 0,
        media_title: data.attributes.media_title ?? null,
        media_artist: data.attributes.media_artist ?? null,
      };
    }
  } catch (err) {
    console.error(`Error fetching ${entityId}:`, err);
  }
  return {
    entity_id: entityId,
    state: "unavailable",
    friendly_name: entityId,
  };
}

// Returns the group structure including current states of all entities
app.get("/api/states", async (req, res) => {
  try {
    const responseGroups = [];

    for (const group of GROUPS) {
      let mainEntityData = null;
      if (group.main_entity) {
        mainEntityData = await fetchEntityState(group.main_entity);
      }

      const entityStates = [];
      if (Array.isArray(group.entities)) {
        for (const entityId of group.entities) {
          entityStates.push(await fetchEntityState(entityId));
        }
      }

      responseGroups.push({
        name: group.name,
        main_entity: mainEntityData,
        entities: entityStates,
      });
    }

    res.json(responseGroups);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "could not fetch states" });
  }
});

app.post("/api/service", async (req, res) => {
  const { entity_id, service, data = {} } = req.body || {};

  if (typeof entity_id !== "string" || !ALLOWED_ENTITIES.has(entity_id)) {
    return res.status(403).json({ error: "entity not allowed" });
  }

  const domain = domainOf(entity_id);
  const allowed = ALLOWED_SERVICES[domain] || [];

  if (!allowed.includes(service)) {
    return res.status(403).json({ error: "service not allowed for this domain" });
  }

  let serviceData = { entity_id };

  if (domain === "light" && service === "turn_on") {
    if (data.brightness_pct !== undefined) {
      const brightness = Number(data.brightness_pct);
      if (!Number.isFinite(brightness) || brightness < 0 || brightness > 100) {
        return res.status(400).json({ error: "invalid brightness" });
      }
      serviceData.brightness_pct = Math.round(brightness);
    }

    if (data.color_temp_kelvin !== undefined) {
      const kelvin = Number(data.color_temp_kelvin);
      if (!Number.isFinite(kelvin) || kelvin < 1000 || kelvin > 10000) {
        return res.status(400).json({ error: "invalid color temperature" });
      }
      serviceData.color_temp_kelvin = Math.round(kelvin);
    }
  }

  try {
    const r = await haFetch(`/api/services/${domain}/${service}`, {
      method: "POST",
      body: JSON.stringify(serviceData),
    });

    if (!r.ok) {
      const errorText = await r.text();
      console.error(`HA rejected ${domain}.${service}:`, errorText);
      return res.status(502).json({ error: "HA rejected the action" });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "could not perform action" });
  }
});

app.listen(PORT, () => {
  console.log(`HA Guest panel running on port ${PORT}, ${GROUPS.length} groups loaded.`);
});
