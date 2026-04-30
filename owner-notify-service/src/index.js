import express from "express";
import bodyParser from "body-parser";
import dotenv from "dotenv";
import { sendSMS } from "./sms.js";
import { sendEmail } from "./email.js";
import { publish } from "./eventBus.js";

dotenv.config();

const app = express();
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: false }));

const PORT = Number(process.env.PORT || 4007);
const OWNER_PHONE = process.env.OWNER_PHONE || "";
const OWNER_EMAIL = process.env.OWNER_EMAIL || "";
const PUBLIC_RECORDS_WEBHOOK_SECRET = process.env.PUBLIC_RECORDS_WEBHOOK_SECRET || "";

const ALLOWED_CHANNELS = new Set(["sms", "email"]);
const OWNER_COMMANDS = new Set(["CALL", "PAUSE", "CLOSE", "INFO"]);

function normalizePhone(value) {
  return String(value || "").replace(/\D/g, "");
}

function parseOwnerCommand(body) {
  const text = String(body || "").trim().toUpperCase();
  if (!text) {
    return { valid: false, reason: "EMPTY_COMMAND" };
  }

  const command = text.split(/\s+/)[0];
  if (!OWNER_COMMANDS.has(command)) {
    return { valid: false, reason: "UNKNOWN_COMMAND", command };
  }

  const actionMap = {
    CALL: "schedule_call",
    PAUSE: "pause_outreach",
    CLOSE: "mark_deal_closed",
    INFO: "send_case_summary"
  };

  return {
    valid: true,
    command,
    action: actionMap[command]
  };
}

function buildTwiml(message) {
  const safe = String(message || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "<")
    .replace(/>/g, ">")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
  return `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${safe}</Message></Response>`;
}

function validateNotifyPayload(payload) {
  const errors = [];

  if (!payload || typeof payload !== "object") {
    errors.push("Request body must be a JSON object.");
    return errors;
  }

  const { subject, message, channels } = payload;

  if (!subject || typeof subject !== "string" || subject.trim().length === 0) {
    errors.push("`subject` is required and must be a non-empty string.");
  }

  if (!message || typeof message !== "string" || message.trim().length === 0) {
    errors.push("`message` is required and must be a non-empty string.");
  }

  if (!Array.isArray(channels) || channels.length === 0) {
    errors.push("`channels` is required and must be a non-empty array.");
  } else {
    const invalid = channels.filter((c) => !ALLOWED_CHANNELS.has(c));
    if (invalid.length > 0) {
      errors.push(`Invalid channel(s): ${invalid.join(", ")}. Allowed: sms, email.`);
    }
  }

  return errors;
}

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "owner-notify-service"
  });
});

app.post("/internal/owner-notify", async (req, res) => {
  const { subject, message, channels } = req.body;
  const validationErrors = validateNotifyPayload(req.body);

  if (validationErrors.length > 0) {
    return res.status(400).json({
      error: "Validation failed",
      details: validationErrors
    });
  }

  if (channels.includes("sms") && !OWNER_PHONE) {
    return res.status(500).json({
      error: "Server misconfiguration: OWNER_PHONE is not set"
    });
  }

  if (channels.includes("email") && !OWNER_EMAIL) {
    return res.status(500).json({
      error: "Server misconfiguration: OWNER_EMAIL is not set"
    });
  }

  try {
    const results = [];

    if (channels.includes("sms")) {
      await sendSMS(OWNER_PHONE, `${subject}: ${message}`);
      results.push("sms");
    }

    if (channels.includes("email")) {
      await sendEmail(OWNER_EMAIL, subject, message);
      results.push("email");
    }

    return res.json({
      status: "sent",
      channels: results
    });
  } catch (err) {
    console.error("Notify error:", err);
    return res.status(500).json({
      error: "Failed to notify owner"
    });
  }
});

app.post("/webhooks/twilio/sms", (req, res) => {
  const from = normalizePhone(req.body?.From);
  const owner = normalizePhone(OWNER_PHONE);
  const body = req.body?.Body || "";
  const messageSid = req.body?.MessageSid || null;

  if (!owner) {
    return res
      .status(500)
      .type("text/xml")
      .send(buildTwiml("System misconfigured: owner phone is missing."));
  }

  if (from !== owner) {
    return res
      .status(403)
      .type("text/xml")
      .send(buildTwiml("Unauthorized sender."));
  }

  const parsed = parseOwnerCommand(body);

  if (!parsed.valid) {
    return res
      .status(200)
      .type("text/xml")
      .send(buildTwiml("Unknown command. Reply with CALL, PAUSE, CLOSE, or INFO."));
  }

  const responsePayload = {
    status: "accepted",
    source: "owner_sms",
    message_sid: messageSid,
    command: parsed.command,
    action: parsed.action
  };

  console.log("Owner command received:", responsePayload);

  return res
    .status(200)
    .type("text/xml")
    .send(buildTwiml(`Command received: ${parsed.command}. Action: ${parsed.action}.`));
});

app.post("/webhooks/public-records/lead", async (req, res) => {
  try {
    if (PUBLIC_RECORDS_WEBHOOK_SECRET) {
      const provided = req.headers["x-webhook-secret"];
      if (provided !== PUBLIC_RECORDS_WEBHOOK_SECRET) {
        return res.status(401).json({
          error: "Unauthorized webhook secret"
        });
      }
    }

    const source = req.body?.source || "public_records";
    const name = String(req.body?.name || "").trim();
    const email = String(req.body?.email || "").trim();
    const phone = String(req.body?.phone || "").trim();
    const address = req.body?.address || null;
    const tags = Array.isArray(req.body?.tags) ? req.body.tags : [];
    const score = Number(req.body?.score || 0);

    if (!name) {
      return res.status(400).json({ error: "`name` is required." });
    }

    if (!email && !phone) {
      return res.status(400).json({ error: "At least one contact field (`email` or `phone`) is required." });
    }

    const lead = {
      source,
      name,
      email: email || null,
      phone: phone || null,
      address,
      tags,
      score
    };

    await publish("events.lead.captured", lead);

    if (score >= 80) {
      const { handleHighPriorityEvent } = await import("./highPriorityHandler.js");
      await handleHighPriorityEvent(lead);
    }

    if (email) {
      await sendEmail(
        email,
        "Thanks for connecting with Equity Shield Advocates",
        `Hi ${name},\n\nThanks for your interest. Our team is reviewing your request and will follow up shortly.\n\n- Equity Shield Advocates`
      );
    }

    return res.status(200).json({
      status: "received",
      source,
      escalated: score >= 80
    });
  } catch (err) {
    console.error("Public records webhook error:", err);
    return res.status(500).json({
      error: "Failed to process public records webhook"
    });
  }
});

app.post("/internal/high-priority-event", async (req, res) => {
  try {
    const { handleHighPriorityEvent } = await import("./highPriorityHandler.js");
    const name = String(req.body?.name || "").trim();
    const score = Number(req.body?.score);

    if (!name || Number.isNaN(score)) {
      return res.status(400).json({
        error: "`name` and numeric `score` are required."
      });
    }

    await handleHighPriorityEvent({ name, score });

    return res.json({
      status: "published",
      topic: "events.notify_owner"
    });
  } catch (err) {
    console.error("High priority publish error:", err);
    return res.status(500).json({
      error: "Failed to publish high-priority event"
    });
  }
});

app.listen(PORT, () => {
  console.log(`Owner Notify Service running on ${PORT}`);
});

