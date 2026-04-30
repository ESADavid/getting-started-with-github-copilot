import twilio from "twilio";

const client = twilio(
  process.env.TWILIO_SID,
  process.env.TWILIO_AUTH
);

export const sendSMS = async (to, body) => {
  return client.messages.create({
    to: `+1${to}`,
    from: process.env.TWILIO_NUMBER,
    body
  });
};
