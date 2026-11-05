#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <SPI.h>
#include <MFRC522.h>
#include <LiquidCrystal_I2C.h>
#include <ArduinoJson.h>
#include <esp_system.h>
#include <time.h>
#include "secrets.h"
MFRC522 reader(5,4);
LiquidCrystal_I2C lcd(0x27,16,2);
String pending;
unsigned attempts=0;
unsigned long retryAt=0;
bool halted=false;
void display(const char* text){lcd.clear();lcd.print(text);}
String uuid(){
 uint8_t b[16];esp_fill_random(b,16);b[6]=(b[6]&0x0f)|0x40;b[8]=(b[8]&0x3f)|0x80;
 char out[37];snprintf(out,sizeof(out),"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]);return String(out);
}
void setup(){
 Serial.begin(115200);SPI.begin();reader.PCD_Init();lcd.init();lcd.backlight();
 if(!strlen(DEVICE_TOKEN)||!strlen(ROOT_CA)||!String(API_URL).startsWith("https://")){display("Check config");halted=true;return;}
 WiFi.begin(WIFI_SSID,WIFI_PASSWORD);unsigned long start=millis();while(WiFi.status()!=WL_CONNECTED&&millis()-start<20000)delay(100);
 if(WiFi.status()!=WL_CONNECTED){display("WiFi failed");halted=true;return;}
 configTime(0,0,"pool.ntp.org","time.google.com");start=millis();while(time(nullptr)<1700000000&&millis()-start<15000)delay(100);
 if(time(nullptr)<1700000000){display("Time failed");halted=true;return;}display("Scan card");
}
void loop(){
 if(halted)return;
 if(pending.length()){
  if((long)(millis()-retryAt)<0)return;
  if(attempts>=3){display("Check app/ACK");halted=true;return;}
  ++attempts;retryAt=millis()+2500;
  WiFiClientSecure client;client.setCACert(ROOT_CA);HTTPClient http;
  if(!http.begin(client,API_URL))return;
  http.setTimeout(8000);http.addHeader("Content-Type","application/json");http.addHeader("Authorization",String("Bearer ")+DEVICE_TOKEN);
  int code=http.POST(pending);String text=http.getString();http.end();
  Serial.printf("HTTP attempt=%u status=%d\n",attempts,code);
  JsonDocument response;bool parsed=!deserializeJson(response,text);
  String outcome=parsed?response["outcome"].as<String>():"";
  if((code==200||code==201)&&(outcome=="RECORDED"||outcome=="ALREADY_RECORDED")){display("Recorded");pending="";delay(1200);display("Scan card");}
  else if(code>=400&&code<500){display("Rejected/check");halted=true;}
  return;
 }
 if(!reader.PICC_IsNewCardPresent()||!reader.PICC_ReadCardSerial())return;
 String uid;for(byte i=0;i<reader.uid.size;++i){if(reader.uid.uidByte[i]<16)uid+='0';uid+=String(reader.uid.uidByte[i],HEX);}uid.toUpperCase();
 JsonDocument event;event["event_id"]=uuid();event["card_uid"]=uid;event["purpose"]="ATTENDANCE";
 serializeJson(event,pending);attempts=0;retryAt=millis();reader.PICC_HaltA();reader.PCD_StopCrypto1();display("Sending");
}
