#include "HX711.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DT  4
#define SCK 5

HX711 scale;

long offset = 0;
float factor = 236.2;

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
BLEAdvertising* pAdvertising = nullptr;

bool deviceConnected = false;
bool oldDeviceConnected = false;

#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcdefab-1234-1234-1234-abcdefabcdef"

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    Serial.println("Client connected");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    Serial.println("Client disconnected");
  }
};

// 5サンプル取得し、最小・最大を除いた中間3点のトリム平均を返す。
// wait_ready() で変換完了を待つことで同一サンプルの重複読みを防ぎ、
// トリムによりノイズ起因のスパイクを排除する。
long readFilteredRaw() {
  const int N = 5;
  long samples[N];
  for (int i = 0; i < N; i++) {
    scale.wait_ready();
    samples[i] = scale.read();
  }
  // 昇順バブルソート
  for (int i = 0; i < N - 1; i++) {
    for (int j = 0; j < N - 1 - i; j++) {
      if (samples[j] > samples[j + 1]) {
        long t = samples[j];
        samples[j] = samples[j + 1];
        samples[j + 1] = t;
      }
    }
  }
  // 最小・最大を除いた中間3点の平均
  return (samples[1] + samples[2] + samples[3]) / 3;
}

void startAdvertisingAgain() {
  delay(300);  // これ重要。切断直後すぐ再開すると不安定なことがある
  pAdvertising->start();
  Serial.println("Advertising restarted");
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  scale.begin(DT, SCK);

  Serial.println("Calibrating zero...");
  long sum = 0;
  for (int i = 0; i < 10; i++) {
    sum += readFilteredRaw();
  }
  offset = sum / 10;
  Serial.print("Offset = ");
  Serial.println(offset);

  BLEDevice::init("CoffeeScale");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();

  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);

  // iPhone/Android両方で安定しやすくする定番設定
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);

  pAdvertising->start();

  Serial.println("BLE scale ready");
}

void loop() {
  // 切断検知後に明示的に再広告
  if (!deviceConnected && oldDeviceConnected) {
    startAdvertisingAgain();
    oldDeviceConnected = deviceConnected;
  }

  // 接続状態更新
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  long raw = readFilteredRaw();
  float weight = (raw - offset) / factor;

  Serial.print("Weight: ");
  Serial.print(weight, 1);
  Serial.println(" g");

  if (deviceConnected) {
    char buffer[20];
    snprintf(buffer, sizeof(buffer), "%.1f", weight);
    pCharacteristic->setValue(buffer);
    pCharacteristic->notify();
  }

  delay(150);
}