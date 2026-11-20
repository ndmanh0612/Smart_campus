#pragma once
#include <ArduinoMqttClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_system.h>
#include <time.h>
#include <sys/time.h>
#include "mqtt_secrets.h"

WiFiClientSecure campusMqttTls;
MqttClient campusMqtt(campusMqttTls);
unsigned long campusNextConnect = 0;
unsigned long campusNextCamera = 0;

void beginCampusMqtt() {
  timeval builtAt = { 1795091136, 0 };
  settimeofday(&builtAt, nullptr);
  campusMqttTls.setCACert(MQTT_ROOT_CA);
  campusMqttTls.setHandshakeTimeout(5);
  campusMqtt.setConnectionTimeout(3000);
  campusMqtt.setId(MQTT_CLIENT_ID);
  campusMqtt.setUsernamePassword(MQTT_USER, MQTT_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
}

bool publishCampusMqtt(const char* suffix, const char* payload) {
  if (!campusMqtt.connected()) return false;
  String topic = String(MQTT_TOPIC) + suffix;
  if (!campusMqtt.beginMessage(topic, strlen(payload), false, 1)) return false;
  campusMqtt.print(payload);
  return campusMqtt.endMessage() == 1;
}

void pollCampusMqtt(bool cameraReady) {
  static unsigned long lastDiagnostic = 0;
  if (millis() - lastDiagnostic >= 5000) {
    lastDiagnostic = millis();
    Serial.printf("NET wifi=%d epoch=%lld mqtt=%d\n", WiFi.status(), (long long)time(nullptr), campusMqtt.connected());
  }
  if (WiFi.status() != WL_CONNECTED) {
    if (campusMqtt.connected()) campusMqtt.stop();
    return;
  }
  unsigned long now = millis();
  if (!campusMqtt.connected()) {
    if (time(nullptr) < 1700000000 || (int32_t)(now - campusNextConnect) < 0) return;
    campusNextConnect = now + 5000;
    if (!campusMqtt.connect(MQTT_HOST, MQTT_PORT)) { Serial.printf("MQTT connect error=%d\n", campusMqtt.connectError()); return; }
    Serial.println("MQTT connected");
    campusNextCamera = now;
  }
  campusMqtt.poll();
  if (cameraReady && (int32_t)(now - campusNextCamera) >= 0) {
    campusNextCamera = now + 5000;
    publishCampusMqtt("/camera", WiFi.localIP().toString().c_str());
  }
}

void publishCampusTap(const uint8_t* uid, size_t size) {
  if (size != 4 && size != 7 && size != 10) return;
  char payload[54];
  uint8_t eventId[16];
  esp_fill_random(eventId, sizeof(eventId));
  for (size_t i = 0; i < sizeof(eventId); i++) {
    snprintf(payload + i * 2, 3, "%02x", eventId[i]);
  }
  payload[32] = ':';
  for (size_t i = 0; i < size; i++) {
    snprintf(payload + 33 + i * 2, 3, "%02X", uid[i]);
  }
  if (!publishCampusMqtt("/tap", payload)) Serial.println("MQTT offline; tap again");
}
