import { publish } from "./eventBus.js";

export const handleHighPriorityEvent = async (lead) => {
  await publish("events.notify_owner", {
    subject: "HOT LEAD",
    message: `Lead ${lead.name} scored ${lead.score}`,
    priority: "high",
    channels: ["sms", "email"]
  });
};
