export const publish = async (topic, payload) => {
  // Minimal event bus stub for local development.
  // Replace with Kafka/RabbitMQ/NATS producer in production.
  console.log(`[eventBus] topic=${topic}`, payload);
  return { delivered: true, topic };
};
