# Owner Notify Service TODO

- [x] Confirm implementation plan
- [x] Scaffold service files (`package.json`, `src/*`, `.env.example`, `README.md`)
- [x] Implement input validation for `/internal/owner-notify`
- [x] Add environment-based owner contact configuration
- [x] Add health endpoint (`GET /health`)
- [x] Run critical-path tests (health, valid notify, invalid payloads, channel-specific paths)
- [x] Summarize results
- [ ] Add two-way SMS webhook endpoint (`POST /webhooks/twilio/sms`)
- [ ] Implement owner command parser (`CALL`, `PAUSE`, `CLOSE`, `INFO`)
- [ ] Add owner verification for inbound SMS
- [ ] Return structured action payload + TwiML acknowledgment
- [ ] Update README for two-way command flow
- [ ] Run full thorough API tests (happy paths, error paths, edge cases)
