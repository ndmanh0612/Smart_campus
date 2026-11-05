#pragma once
// Copy to secrets.h (ignored), then provision from your own local environment.
const char* WIFI_SSID = "";
const char* WIFI_PASSWORD = "";
const char* DEVICE_ID = "";
const char* DEVICE_TOKEN = "";
const char* DEVICE_ROLE = "RFID_ENROLLMENT"; // Initial label only; backend config is authoritative.
const char* API_ORIGIN = "https://staging.example.invalid";
const char* ROOT_CA = ""; // PEM root CA. Never use setInsecure().
const uint8_t LCD_I2C_ADDRESS = 0x27; // Confirm with I2C scan before use.
