import sgMail from "@sendgrid/mail";

sgMail.setApiKey(process.env.SENDGRID_KEY);

export const sendEmail = async (to, subject, text) => {
  const msg = {
    to,
    from: process.env.SENDGRID_FROM,
    subject,
    text
  };

  return sgMail.send(msg);
};
