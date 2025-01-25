import Foundation
import BoostBLEKit
import CoreBluetooth

struct MoveHubService {
    
    static let serviceUuid = CBUUID(string: GATT.serviceUuid)
    static let characteristicUuid = CBUUID(string: GATT.characteristicUuid)
}

protocol HubManagerDelegate: AnyObject {
    
    func didConnect(peripheral: CBPeripheral)
    func didFailToConnect(peripheral: CBPeripheral, error: Error?)
    func didDisconnect(peripheral: CBPeripheral, error: Error?)
    func didUpdate(notification: BoostBLEKit.Notification)
}

class UnknownHub: Hub {
    
    let systemTypeAndDeviceNumber: UInt8
    
    init(systemTypeAndDeviceNumber: UInt8) {
        self.systemTypeAndDeviceNumber = systemTypeAndDeviceNumber
    }
    
    var connectedIOs: [PortId: IOType] = [:]
    let portMap: [BoostBLEKit.Port: PortId] = [:]
}

class HubManager: NSObject {
    
    weak var delegate: HubManagerDelegate?
    
    private var centralManager: CBCentralManager!
    private var peripherals: [CBPeripheral] = []
    private var characteristics: [CBPeripheral: CBCharacteristic] = [:]
    
    var connectedHubs: [CBPeripheral: Hub] = [:]
    var sensorValues: [CBPeripheral: [PortId: Data]] = [:]
    
    var isConnectedHub: Bool {
        return !peripherals.isEmpty
    }
    
    init(delegate: HubManagerDelegate) {
        super.init()
        
        self.delegate = delegate
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScan() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [MoveHubService.serviceUuid], options: nil)
        }
    }
    
    func stopScan() {
        centralManager.stopScan()
    }
    
    private func connect(peripheral: CBPeripheral, advertisementData: [String : Any]) {
        guard !peripherals.contains(peripheral) else { return }
        
        guard let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data else { return }
        guard manufacturerData.count == 8 else { return }
        guard manufacturerData[0] == 0x97, manufacturerData[1] == 0x03 else { return }
        
        let hubType = HubType(manufacturerData: manufacturerData)
        
        switch hubType {
        case .boost:
            connectedHubs[peripheral] = Boost.MoveHub()
        case .boostV1:
            connectedHubs[peripheral] = Boost.MoveHubV1()
        case .poweredUp:
            connectedHubs[peripheral] = PoweredUp.SmartHub()
        case .duploTrain:
            connectedHubs[peripheral] = Duplo.TrainBase()
        case .controlPlus:
            connectedHubs[peripheral] = ControlPlus.SmartHub()
        case .remoteControl:
            connectedHubs[peripheral] = PoweredUp.RemoteControl()
        case .mario:
            connectedHubs[peripheral] = SuperMario.Mario()
        case .luigi:
            connectedHubs[peripheral] = SuperMario.Luigi()
//        case .peach:
//            connectedHubs[peripheral] = SuperMario.Peach()
        case .spikeEssential:
            connectedHubs[peripheral] = Spike.EssentialHub()
        case .none:
            let systemTypeAndDeviceNumber = manufacturerData[3]
            print(String(format: "Unknown Hub (System Type and Device Number: 0x%02x)", systemTypeAndDeviceNumber))
            connectedHubs[peripheral] = UnknownHub(systemTypeAndDeviceNumber: systemTypeAndDeviceNumber)
        }
        
        peripherals.append(peripheral)
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect(hub: CBPeripheral) {
        if let index = peripherals.firstIndex(of: hub) {
            centralManager.cancelPeripheralConnection(hub)
            peripherals.remove(at: index)
            characteristics[hub] = nil
            connectedHubs[hub] = nil
        }
    }
    
    private func set(characteristic: CBCharacteristic, for peripheral: CBPeripheral) {
        if characteristic.properties.contains([.write, .notify]) {
            characteristics[peripheral] = characteristic
            peripheral.setNotifyValue(true, for: characteristic)

            DispatchQueue.main.async { [weak self] in
                self?.write(data: HubPropertiesCommand(property: .advertisingName, operation: .enableUpdates).data, to: peripheral)
                self?.write(data: HubPropertiesCommand(property: .firmwareVersion, operation: .requestUpdate).data, to: peripheral)
                self?.write(data: HubPropertiesCommand(property: .batteryVoltage, operation: .enableUpdates).data, to: peripheral)
            }
        }
    }
    
    private func receive(notification: BoostBLEKit.Notification, from peripheral: CBPeripheral) {
        print(notification)
        switch notification {
        case .hubProperty:
            break
            
        case .connected(let portId, let ioType):
            connectedHubs[peripheral]?.connectedIOs[portId] = ioType
            if let command = connectedHubs[peripheral]?.subscribeCommand(portId: portId) {
                write(data: command.data, to: peripheral)
            }
            
        case .disconnected(let portId):
            connectedHubs[peripheral]?.connectedIOs[portId] = nil
            sensorValues[peripheral]?[portId] = nil
            if let command = connectedHubs[peripheral]?.unsubscribeCommand(portId: portId) {
                write(data: command.data, to: peripheral)
            }
            
        case .sensorValue(let portId, let value):
            sensorValues[peripheral]?[portId] = value
        }
    }
    
    func write(data: Data, to peripheral: CBPeripheral) {
        print("->", data.hexString)
        if let characteristic = characteristics[peripheral] {
            DispatchQueue.main.async {
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
        }
    }
}

extension HubManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("unknown")
        case .resetting:
            print("resetting")
        case .unsupported:
            print("unsupported")
        case .unauthorized:
            print("unauthorized")
        case .poweredOff:
            print("poweredOff")
        case .poweredOn:
            print("poweredOn")
        @unknown default:
            print("@unknown default")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(#function, peripheral)
        print("RSSI:", RSSI)
        print("advertisementData:", advertisementData)
        connect(peripheral: peripheral, advertisementData: advertisementData)
        stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([MoveHubService.serviceUuid])
        delegate?.didConnect(peripheral: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print(#function, peripheral, error)
        }
        delegate?.didFailToConnect(peripheral: peripheral, error: error)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print(#function, peripheral, error)
        }
        delegate?.didDisconnect(peripheral: peripheral, error: error)
    }
}

extension HubManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let service = peripheral.services?.first(where: { $0.uuid == MoveHubService.serviceUuid }) {
            peripheral.discoverCharacteristics([MoveHubService.characteristicUuid], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristic = service.characteristics?.first(where: { $0.uuid == MoveHubService.characteristicUuid }) {
            set(characteristic: characteristic, for: peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        print("<-", data.hexString)
        if let notification = Notification(data: data) {
            receive(notification: notification, from: peripheral)
            delegate?.didUpdate(notification: notification)
        }
    }
}
