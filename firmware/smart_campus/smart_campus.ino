#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <SPI.h>
#include <Wire.h>
#include <MFRC522.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <esp_system.h>
#include <time.h>
#include "secrets.h"

MFRC522 reader(5, 4);
LiquidCrystal_I2C lcd(LCD_I2C_ADDRESS, 16, 2);
Preferences storage;
String pending, actionId, contextId, deviceRole, lastUid;
unsigned configVersion = 0, attempts = 0;
unsigned long nextPoll = 0, retryAt = 0, reconnectAt = 0, lastScanAt = 0;
bool configured = false, configValid = false;

void show(const String& first, const String& second = "") {
  lcd.clear(); lcd.setCursor(0, 0); lcd.print(first.substring(0, 16));
  lcd.setCursor(0, 1); lcd.print(second.substring(0, 16));
}
String uuid() {
  uint8_t b[16]; esp_fill_random(b, 16); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  char out[37];
  snprintf(out, sizeof(out), "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]);
  return String(out);
}
String timestamp() {
  time_t now = time(nullptr); struct tm utc; gmtime_r(&now, &utc); char out[25];
  strftime(out, sizeof(out), "%Y-%m-%dT%H:%M:%SZ", &utc); return String(out);
}
int request(const String& path, JsonDocument& response, const String& payload = "", const String& key = "") {
  if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) return -1;
  WiFiClientSecure client; client.setCACert(ROOT_CA); HTTPClient http;
  if (!http.begin(client, String(API_ORIGIN) + "/api/v1" + path)) return -2;
  http.setConnectTimeout(4000); http.setTimeout(8000);
  http.addHeader("Authorization", String("Bearer ") + DEVICE_TOKEN);
  http.addHeader("Content-Type", "application/json");
  if (key.length()) http.addHeader("Idempotency-Key", key);
  const int code = payload.length() ? http.POST(payload) : http.GET();
  const String body = http.getString(); http.end();
  Serial.printf("HTTP status=%d\n", code); // Never print UID, payload, Wi-Fi or credentials.
  if (deserializeJson(response, body)) return -3;
  return code;
}
void clearPending() { pending = ""; attempts = 0; storage.remove("pending"); }
void rememberAction(const String& value) { actionId = value; storage.putString("action", actionId); }
void accepted(JsonDocument& response) {
  const String event = response["data"]["eventId"] | "";
  JsonDocument original; deserializeJson(original, pending);
  if (event != original["eventId"].as<String>()) { show("SAI ACK", "XEM UNG DUNG"); return; }
  rememberAction(response["data"]["actionId"] | ""); clearPending();
  show("THE HOP LE", "CHO XAC NHAN"); nextPoll = millis() + 1000;
}
void submitPending() {
  if ((long)(millis() - retryAt) < 0) return;
  JsonDocument response;
  if (attempts >= 3) {
    // Read-only recovery after retry exhaustion, including a reboot with an uncertain commit.
    JsonDocument original; deserializeJson(original, pending);
    const int code = request(String("/device-events/") + original["eventId"].as<String>(), response);
    if (code == 200) {
      JsonDocument recovered;
      recovered["data"] = response["data"]["response"]["data"];
      if (!recovered["data"].isNull()) accepted(recovered);
      else { clearPending(); show("THE BI TU CHOI", "QUET LAI KHI CAN"); }
    } else show("CHUA RO KET QUA", "NHAN r DE THU LAI");
    retryAt = millis() + 5000; return;
  }
  ++attempts;
  const int code = request("/device-events", response, pending);
  if (code == 202 || code == 200) accepted(response);
  else if (code >= 400 && code < 500 && code != 429) {
    const String error = response["error"]["code"] | "";
    show(error == "CARD_NOT_ACTIVE" ? "THE KHONG HOP LE" : "YEU CAU BI TU CHOI", "XEM UNG DUNG");
    clearPending(); contextId = ""; configured = false; nextPoll = millis() + 2500;
  } else { show("LOI MANG / ACK", "DANG THU LAI"); }
  retryAt = millis() + 1500 * (1U << (attempts > 2 ? 2 : attempts));
}
void pollConfig() {
  JsonDocument response;
  if (request("/device/config", response) != 200) { configured = false; show("MAT KET NOI API", "KHONG XU LY OFFLINE"); return; }
  if (response["data"]["deviceId"].as<String>() != DEVICE_ID) { configured = false; show("SAI DEVICE_ID"); return; }
  deviceRole = response["data"]["role"].as<String>(); configVersion = response["data"]["configVersion"];
  if (!(response["data"]["acknowledged"] | false)) {
    JsonDocument ack, result; ack["deviceId"] = DEVICE_ID; ack["configVersion"] = configVersion;
    String body; serializeJson(ack, body);
    if (request("/device/config-ack", result, body, uuid()) != 200) { configured = false; return; }
  }
  contextId = response["data"]["context"]["id"] | ""; configured = true;
  show(contextId.length() ? "MOI QUET THE" : "CHO NGHIEP VU", deviceRole);
}
void pollAction() {
  JsonDocument response;
  if (request("/device/actions/" + actionId, response) != 200) { show("CHO DOI SOAT", "XEM UNG DUNG"); return; }
  show(response["data"]["lcdLines"][0] | "CHO XAC NHAN", response["data"]["lcdLines"][1] | "XEM UNG DUNG");
  if (response["data"]["terminal"] | false) { rememberAction(""); contextId = ""; configured = false; nextPoll = millis() + 2500; }
}
void readCard() {
  if (!configured || !contextId.length() || !reader.PICC_IsNewCardPresent() || !reader.PICC_ReadCardSerial()) return;
  String uid;
  for (byte i = 0; i < reader.uid.size; ++i) { if (reader.uid.uidByte[i] < 16) uid += '0'; uid += String(reader.uid.uidByte[i], HEX); }
  reader.PICC_HaltA(); reader.PCD_StopCrypto1(); uid.toUpperCase();
  if (uid == lastUid && millis() - lastScanAt < 2500) return;
  lastUid = uid; lastScanAt = millis();
  JsonDocument challenge, result; challenge["deviceId"] = DEVICE_ID; challenge["configVersion"] = configVersion; challenge["contextId"] = contextId;
  String payload; serializeJson(challenge, payload);
  if (request("/device/challenges", result, payload, uuid()) != 200) { configured = false; show("KHONG CO PHIEN", "TAO NGHIEP VU TRUOC"); return; }
  JsonDocument event; event["schemaVersion"] = 1; event["eventId"] = uuid(); event["deviceId"] = DEVICE_ID;
  event["deviceRole"] = deviceRole; event["configVersion"] = configVersion; event["contextId"] = contextId;
  event["challengeId"] = result["data"]["challengeId"]; event["nonce"] = result["data"]["nonce"];
  event["occurredAt"] = timestamp(); event["credential"]["type"] = "RFID_UID"; event["credential"]["uid"] = uid;
  serializeJson(event, pending); storage.putString("pending", pending); attempts = 0; retryAt = millis(); show("DANG GUI THE", "CHO ACK BACKEND");
}
void setup() {
  Serial.begin(115200); Wire.begin(21, 22); SPI.begin(18, 19, 23, 5); reader.PCD_Init(); lcd.init(); lcd.backlight();
  if (!strlen(DEVICE_ID) || !strlen(DEVICE_TOKEN) || !strlen(ROOT_CA) || !String(API_ORIGIN).startsWith("https://")) { show("THIEU CAU HINH", "KIEM TRA secrets.h"); return; }
  if (!storage.begin("campus", false)) { show("LOI LUU TRU NVS", "KHONG XU LY THE"); return; }
  configValid = true; pending = storage.getString("pending", ""); actionId = storage.getString("action", "");
  WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID, WIFI_PASSWORD); configTime(0, 0, "pool.ntp.org", "time.google.com");
  show("KET NOI WIFI", DEVICE_ROLE);
}
void loop() {
  if (!configValid) { delay(100); return; }
  if (Serial.available() && Serial.read() == 'r') { attempts = 0; retryAt = 0; } // Same event is retried; no new payment/event.
  if (WiFi.status() != WL_CONNECTED) {
    if ((long)(millis() - reconnectAt) >= 0) { WiFi.reconnect(); reconnectAt = millis() + 5000; show("MAT WIFI", "KHONG XU LY OFFLINE"); }
    delay(20); return;
  }
  if (time(nullptr) < 1700000000) { show("CHO DONG BO GIO", "TLS CHUA SAN SANG"); delay(200); return; }
  if (pending.length()) { submitPending(); delay(20); return; }
  if ((long)(millis() - nextPoll) >= 0) { nextPoll = millis() + 2000; if (actionId.length()) pollAction(); else pollConfig(); }
  if (!actionId.length()) readCard();
  delay(20);
}
