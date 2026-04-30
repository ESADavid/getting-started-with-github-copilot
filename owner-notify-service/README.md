# owner-notify-service

Owner notification microservice for Equity Shield Advocates (ESA).  
Provides an internal endpoint to notify the owner through SMS and/or email when high-priority events occur.

## Features

- `POST /internal/owner-notify` for owner escalation
- Input validation for subject/message/channels
- Environment-based owner contact config
- `GET /health` status endpoint
- Stub providers for SMS and email (safe for local testing)

## API

### Health Check

`GET /health`

Response:
```json
{
  "status": "ok",
  "service": "owner-notify-service"
}
```

### Notify Owner

`POST /internal/owner-notify`

Request body:
```json
{
  "subject": "Hot Lead",
  "message": "Lead Jane Doe scored 91",
  "priority": "high",
  "channels": ["sms", "email"]
}
```

Notes:
- `priority` is accepted but currently informational only.
- `channels` must include one or both of: `sms`, `email`.

Success response:
```json
{
  "status": "sent",
  "channels": ["sms", "email"]
}
```

Validation error response (`400`):
```json
{
  "error": "Validation failed",
  "details": [
    "`subject` is required and must be a non-empty string."
  ]
}
```

## Environment Variables

Create a `.env` file and configure:

- `PORT` - Service port (default: `4007`)
- `OWNER_PHONE` - Owner destination phone for SMS notifications
- `OWNER_EMAIL` - Owner destination email for email notifications
- `TWILIO_SID` - Twilio Account SID
- `TWILIO_AUTH` - Twilio Auth Token
- `TWILIO_NUMBER` - Twilio sender number in E.164 format (example: `+17045551234`)

## Local Development

1. Install dependencies:
```bash
npm install
```

2. Configure `.env` with owner + Twilio variables.

3. Run the service:
```bash
npm start
```

Service runs at: `http://localhost:4007`

## Quick Test (curl)

Health:
```bash
curl http://localhost:4007/health
```

Notify:
```bash
curl -X POST http://localhost:4007/internal/owner-notify ^
  -H "Content-Type: application/json" ^
  -d "{\"subject\":\"Hot Lead\",\"message\":\"Lead scored 95\",\"priority\":\"high\",\"channels\":[\"sms\",\"email\"]}"
```

## Production Integration Notes

- `src/sms.js` uses Twilio and requires valid Twilio credentials in `.env`.
- Replace `src/email.js` with SendGrid or AWS SES implementation.
- Add request authentication for internal routes (service token or mTLS).
- Add persistent audit logging for compliance.
