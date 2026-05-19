import React, { createContext, useContext, useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Platform, PermissionsAndroid, Alert } from 'react-native';
import { BleManager } from 'react-native-ble-plx';

// Поддерживаемые платы и их характеристики
const SUPPORTED_DEVICES = {
  // ESP32-C3 (стандартные UUID)
  'ESP32-C3': {
    serviceUUID: '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
    charRX: 'beb5483e-36e1-4688-b7f5-ea07361b26a8',
    charTX: 'beb5483e-36e1-4688-b7f5-ea07361b26a9',
    namePrefix: ['ESP32', 'Drone', 'C3']
  },
  // Arduino Nano 33 BLE
  'ArduinoNano33': {
    serviceUUID: '19b10000-e8f2-537e-4f6c-d104768a1214',
    charRX: '19b10001-e8f2-537e-4f6c-d104768a1214',
    charTX: '19b10002-e8f2-537e-4f6c-d104768a1214',
    namePrefix: ['Nano', 'Arduino', 'Drone']
  },
  // HM-10 модуль (обычно на Arduino)
  'HM10': {
    serviceUUID: '0000ffe0-0000-1000-8000-00805f9b34fb',
    charRX: '0000ffe1-0000-1000-8000-00805f9b34fb',
    charTX: '0000ffe1-0000-1000-8000-00805f9b34fb',
    namePrefix: ['HMSoft', 'BT05', 'MLT-BT05', 'DSD TECH']
  },
  // NRF52832
  'NRF52832': {
    serviceUUID: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    charRX: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    charTX: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
    namePrefix: ['Nordic', 'nRF', 'Drone']
  }
};

// Универсальная функция поиска подходящего протокола
const detectDeviceType = (deviceName = '', deviceId = '') => {
  const name = deviceName || deviceId || '';
  
  for (const [type, config] of Object.entries(SUPPORTED_DEVICES)) {
    const matched = config.namePrefix.some(prefix => 
      name.toUpperCase().includes(prefix.toUpperCase())
    );
    if (matched) return type;
  }
  
  // Если не определили — пробуем универсальное сканирование сервисов
  return 'AUTO';
};

const clamp = (v, lo, hi) => v < lo ? lo : v > hi ? hi : v;

const BLEContext = createContext(null);

export const BLEProvider = ({ children }) => {
  const [manager] = useState(() => new BleManager());
  const [connectedDevice, setConnectedDevice] = useState(null);
  const [deviceConfig, setDeviceConfig] = useState(null); // конфиг текущей платы
  const [lastStatus, setLastStatus] = useState(null);
  const [commandHistory, setCommandHistory] = useState([]);
  const [isScanning, setIsScanning] = useState(false);
  const [availableDevices, setAvailableDevices] = useState([]);
  
  const disconnectSubRef = useRef(null);
  const monitorSubRef = useRef(null);
  
  const logCommandRef = useRef((entry) => {
    setCommandHistory(prev => {
      const updated = prev.concat([entry]);
      return updated.length > 100 ? updated.slice(-100) : updated;
    });
  });

  // Запрос разрешений
  const requestPermissions = useCallback(async () => {
    if (Platform.OS === 'android') {
      try {
        if (Platform.Version >= 31) {
          const result = await PermissionsAndroid.requestMultiple([
            PermissionsAndroid.PERMISSIONS.BLUETOOTH_SCAN,
            PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT,
            PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
          ]);
          return Object.values(result).every(r => r === 'granted');
        } else {
          const result = await PermissionsAndroid.request(
            PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION
          );
          return result === 'granted';
        }
      } catch (err) {
        console.warn('Permission error:', err);
        return false;
      }
    }
    return true;
  }, []);

  // Сканирование устройств
  const scan = useCallback(async (timeoutMs = 8000) => {
    const granted = await requestPermissions();
    if (!granted) {
      Alert.alert(
        'Permissions Required',
        'Bluetooth and Location permissions are required to scan for devices.',
        [{ text: 'OK' }]
      );
      return [];
    }

    setIsScanning(true);
    setAvailableDevices([]);
    
    return new Promise((resolve) => {
      const devices = [];
      
      manager.startDeviceScan(null, { allowDuplicates: false }, (error, device) => {
        if (error) {
          console.log('Scan error:', error);
          return;
        }
        
        if (device && (device.name || device.localName)) {
          const exists = devices.find(d => d.id === device.id);
          if (!exists) {
            const newDevice = {
              id: device.id,
              name: device.name || device.localName || 'Unknown Device',
              rssi: device.rssi || 0,
              detectedType: detectDeviceType(device.name || device.localName, device.id),
              rawDevice: device
            };
            devices.push(newDevice);
            setAvailableDevices([...devices]);
          }
        }
      });

      setTimeout(() => {
        manager.stopDeviceScan();
        setIsScanning(false);
        resolve(devices);
      }, timeoutMs);
    });
  }, [manager, requestPermissions]);

  // Универсальное подключение
  const connectToDevice = useCallback(async (device) => {
    try {
      // Подключаемся к устройству
      const connected = await manager.connectToDevice(device.id);
      await connected.discoverAllServicesAndCharacteristics();
      
      // Получаем все сервисы и характеристики
      const services = await connected.services();
      let rxChar = null;
      let txChar = null;
      let serviceUUID = null;
      
      // Пробуем определить тип устройства и найти нужные характеристики
      const deviceType = detectDeviceType(device.name, device.id);
      
      if (deviceType !== 'AUTO' && SUPPORTED_DEVICES[deviceType]) {
        // Используем известную конфигурацию
        const config = SUPPORTED_DEVICES[deviceType];
        serviceUUID = config.serviceUUID;
        rxChar = config.charRX;
        txChar = config.charTX;
        setDeviceConfig({ type: deviceType, config });
      } else {
        // Автоопределение: ищем сервисы с характеристиками WRITE и NOTIFY
        for (const service of services) {
          const characteristics = await service.characteristics();
          
          for (const char of characteristics) {
            const props = char.properties || {};
            
            if (!txChar && (props.Notify || props.Indicate)) {
              txChar = char.uuid;
              serviceUUID = service.uuid;
            }
            
            if (!rxChar && (props.Write || props.WriteWithoutResponse)) {
              rxChar = char.uuid;
              if (!serviceUUID) serviceUUID = service.uuid;
            }
            
            if (rxChar && txChar && serviceUUID) break;
          }
          if (rxChar && txChar && serviceUUID) break;
        }
        
        if (!rxChar || !txChar) {
          throw new Error('Cannot find required BLE characteristics. Make sure the device is properly configured.');
        }
        
        setDeviceConfig({
          type: 'CUSTOM',
          config: { serviceUUID, charRX: rxChar, charTX: txChar }
        });
      }
      
      // Сохраняем данные устройства
      const deviceInfo = {
        id: device.id,
        name: device.name || 'Unknown',
        rssi: device.rssi,
        serviceUUID,
        rxChar,
        txChar
      };
      
      setConnectedDevice(deviceInfo);
      
      // Подписываемся на уведомления
      if (monitorSubRef.current) {
        monitorSubRef.current.remove();
      }
      
      monitorSubRef.current = connected.monitorCharacteristicForService(
        serviceUUID,
        txChar,
        (error, characteristic) => {
          if (error) {
            console.log('Notification error:', error);
            return;
          }
          if (characteristic?.value) {
            try {
              const msg = atob(characteristic.value);
              setLastStatus({ ok: true, msg });
              logCommandRef.current({
                type: 'received',
                cmd: msg,
                time: new Date().toLocaleTimeString()
              });
            } catch (e) {
              console.log('Decode error:', e);
            }
          }
        }
      );

      // Обработка отключения
      if (disconnectSubRef.current) {
        disconnectSubRef.current.remove();
      }
      
      disconnectSubRef.current = manager.onDeviceDisconnected(
        device.id,
        (error, disconnectedDevice) => {
          setConnectedDevice(null);
          setDeviceConfig(null);
          setLastStatus({ ok: false, msg: 'Device disconnected' });
          if (monitorSubRef.current) {
            monitorSubRef.current.remove();
            monitorSubRef.current = null;
          }
        }
      );

      return deviceInfo;
    } catch (error) {
      console.log('Connection error:', error);
      throw new Error(error.message || 'Connection failed');
    }
  }, [manager]);

  // Отключение
  const disconnectFromDevice = useCallback(async () => {
    if (!connectedDevice) return;
    
    try {
      if (monitorSubRef.current) {
        monitorSubRef.current.remove();
        monitorSubRef.current = null;
      }
      
      if (disconnectSubRef.current) {
        disconnectSubRef.current.remove();
        disconnectSubRef.current = null;
      }
      
      await manager.cancelDeviceConnection(connectedDevice.id);
    } catch (err) {
      console.log('Disconnect error:', err);
    } finally {
      setConnectedDevice(null);
      setDeviceConfig(null);
      setLastStatus(null);
    }
  }, [manager, connectedDevice]);

  // Отправка команды
  const sendControl = useCallback(async (throttle, elevator, aileron) => {
    if (!connectedDevice || !deviceConfig) {
      console.log('Not connected or no device config');
      return;
    }
    
    const { serviceUUID, rxChar } = connectedDevice;
    
    if (!serviceUUID || !rxChar) {
      console.log('Missing service UUID or RX characteristic');
      return;
    }
    
    const t = Math.round(clamp(throttle, 0, 255));
    const e = Math.round(clamp(elevator, 0, 180));
    const a = Math.round(clamp(aileron, 0, 180));
    
    // Универсальный формат: всегда отправляем SET
    const packet = `SET ${t} ${e} ${a}`;
    
    logCommandRef.current({
      type: 'sent',
      cmd: packet,
      time: new Date().toLocaleTimeString()
    });
    
    try {
      await manager.writeCharacteristicWithoutResponseForService(
        connectedDevice.id,
        serviceUUID,
        rxChar,
        btoa(packet) // Base64 кодирование
      );
    } catch (error) {
      console.log('BLE write error:', error);
      // Пробуем обычную запись с ответом
      try {
        await manager.writeCharacteristicWithResponseForService(
          connectedDevice.id,
          serviceUUID,
          rxChar,
          btoa(packet)
        );
      } catch (err2) {
        console.log('BLE write with response error:', err2);
      }
    }
  }, [manager, connectedDevice, deviceConfig]);

  // Отправка произвольной команды (для разных плат)
  const sendCustomCommand = useCallback(async (command) => {
    if (!connectedDevice || !deviceConfig) {
      console.log('Not connected');
      return;
    }
    
    const { serviceUUID, rxChar } = connectedDevice;
    
    logCommandRef.current({
      type: 'sent',
      cmd: command,
      time: new Date().toLocaleTimeString()
    });
    
    try {
      await manager.writeCharacteristicWithoutResponseForService(
        connectedDevice.id,
        serviceUUID,
        rxChar,
        btoa(command)
      );
    } catch (error) {
      console.log('Custom command error:', error);
      try {
        await manager.writeCharacteristicWithResponseForService(
          connectedDevice.id,
          serviceUUID,
          rxChar,
          btoa(command)
        );
      } catch (err2) {
        console.log('Custom command retry error:', err2);
      }
    }
  }, [manager, connectedDevice, deviceConfig]);

  // Очистка при размонтировании
  useEffect(() => {
    return () => {
      if (monitorSubRef.current) {
        monitorSubRef.current.remove();
      }
      if (disconnectSubRef.current) {
        disconnectSubRef.current.remove();
      }
      manager.destroy();
    };
  }, [manager]);

  const value = useMemo(() => ({
    bt: { scan },
    connectedDevice,
    deviceConfig,
    lastStatus,
    connectToDevice,
    disconnectFromDevice,
    sendControl,
    sendCustomCommand,
    commandHistory,
    clearHistory: () => setCommandHistory([]),
    isScanning,
    availableDevices,
    supportedDevices: SUPPORTED_DEVICES
  }), [
    scan, connectedDevice, deviceConfig, lastStatus,
    connectToDevice, disconnectFromDevice, sendControl,
    sendCustomCommand, commandHistory, isScanning, availableDevices
  ]);

  return (
    <BLEContext.Provider value={value}>
      {children}
    </BLEContext.Provider>
  );
};

export const useBLE = () => {
  const context = useContext(BLEContext);
  if (!context) {
    throw new Error('useBLE must be used within a BLEProvider');
  }
  return context;
};

export default BLEContext;
