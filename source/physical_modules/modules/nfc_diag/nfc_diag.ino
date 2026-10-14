#include <MFRC522DriverI2C.h>
#include <MFRC522Debug.h>
#include <MFRC522v2.h>
#include <Wire.h>

// Standalone NFC bring-up diagnostic (not a bus module). Confirms the MFRC522
// answers on I2C, reports its version register, and dumps any presented tag's
// type + UID + full page memory so we can confirm the 25 mm tags are NTAG21x
// before pivoting the module_2 firmware. Read-only: it never writes a tag.
//
// Wiring assumptions (edit to match the board):
//   SDA -> GPIO21, SCL -> GPIO22, reader I2C address 0x28.
// Flash with:  make upload MODULE=nfc_diag PORT=/dev/cu.usbserial-XXXX
// then:        make monitor

static constexpr uint8_t kSda = 21;
static constexpr uint8_t kScl = 22;
static constexpr uint8_t kAddress = 0x28;

MFRC522DriverI2C driver{kAddress, Wire};
MFRC522 reader{driver};

static void scan_i2c() {
  Serial.println(F("I2C scan:"));
  uint8_t found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.print(F("  device at 0x"));
      Serial.println(addr, HEX);
      found++;
    }
  }
  if (found == 0) {
    Serial.println(F("  none (check power, level shifter, pull-ups, SDA/SCL)"));
  }
}

void setup() {
  Serial.begin(115200);
  delay(400);
  Wire.begin(kSda, kScl);
  Serial.println(F("=== NFC diagnostic ==="));
  scan_i2c();

  reader.PCD_Init();
  Serial.print(F("Reader version: "));
  MFRC522Debug::PCD_DumpVersionToSerial(reader, Serial);
  Serial.println(F("Place a tag on the reader..."));
}

void loop() {
  if (reader.PICC_IsNewCardPresent() && reader.PICC_ReadCardSerial()) {
    Serial.println();
    Serial.println(F("--- tag ---"));
    MFRC522Debug::PICC_DumpToSerial(reader, Serial, &reader.uid);
    reader.PICC_HaltA();
  }
  delay(200);
}
