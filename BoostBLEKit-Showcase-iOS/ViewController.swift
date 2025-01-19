import UIKit
import CoreBluetooth
import BoostBLEKit

class ViewController: UIViewController {

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var firmwareVersionLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    @IBOutlet weak var powerLabel: UILabel!
    @IBOutlet weak var commandTextField: UITextField!
    @IBOutlet weak var hubSelectionDropdown: UIPickerView!
    
    private var hubManager: HubManager!
    private var power: Int8 = 0
    private var connectedHubs: [CBPeripheral] = []
    private var selectedHub: CBPeripheral?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        hubManager = HubManager(delegate: self)
        
        resetLabels()
        
        setPower(power: 0)
        
        hubSelectionDropdown.delegate = self
        hubSelectionDropdown.dataSource = self
    }
    
    private func resetLabels() {
        nameLabel.text = ""
        firmwareVersionLabel.text = ""
        batteryLabel.text = ""
    }
    
    private func setPower(power: Int8) {
        self.power = power
        powerLabel.text = "\(power)"
        
        guard let hub = hubManager.connectedHub(for: selectedHub) else { return }
        
        let ports: [BoostBLEKit.Port] = [.A, .B, .C, .D]
        for port in ports {
            if let command = hub.motorStartPowerCommand(port: port, power: power) {
                hubManager.write(data: command.data, to: selectedHub)
            }
        }
    }
    
    @IBAction func pushConnectButton(_ sender: Any) {
        if let selectedHub = selectedHub, hubManager.isConnectedHub(selectedHub) {
            hubManager.disconnect(hub: selectedHub)
        } else {
            hubManager.startScan()
        }
    }
    
    @IBAction func pushPlusButton(_ sender: Any) {
        let power = min(self.power + 10, 100)
        setPower(power: power)
    }
    
    @IBAction func pushMinusButton(_ sender: Any) {
        let power = max(self.power - 10, -100)
        setPower(power: power)
    }
    
    @IBAction func pushStopButton(_ sender: Any) {
        setPower(power: 0)
    }
    
    @IBAction func pushSendButton(_ sender: Any) {
        if let data = commandTextField.text.flatMap(Data.init(hexString:)) {
            hubManager.write(data: data, to: selectedHub)
        }
    }
}

extension ViewController: HubManagerDelegate {
    func didConnect(peripheral: CBPeripheral) {
        connectedHubs.append(peripheral)
        hubSelectionDropdown.reloadAllComponents()
        if selectedHub == nil {
            selectedHub = peripheral
            hubSelectionDropdown.selectRow(connectedHubs.count - 1, inComponent: 0, animated: true)
        }
        connectButton.setTitle("Disconnect", for: .normal)
        nameLabel.text = peripheral.name ?? "Unknown"
    }
    
    func didFailToConnect(peripheral: CBPeripheral, error: Error?) {
        if let index = connectedHubs.firstIndex(of: peripheral) {
            connectedHubs.remove(at: index)
            hubSelectionDropdown.reloadAllComponents()
        }
        connectButton.setTitle("Connect", for: .normal)
        resetLabels()
    }
    
    func didDisconnect(peripheral: CBPeripheral, error: Error?) {
        if let index = connectedHubs.firstIndex(of: peripheral) {
            connectedHubs.remove(at: index)
            hubSelectionDropdown.reloadAllComponents()
        }
        if selectedHub == peripheral {
            selectedHub = connectedHubs.first
            if let selectedHub = selectedHub {
                hubSelectionDropdown.selectRow(0, inComponent: 0, animated: true)
            }
        }
        connectButton.setTitle("Connect", for: .normal)
        resetLabels()
    }
    
    func didUpdate(notification: BoostBLEKit.Notification) {
        switch notification {
        case .hubProperty(let hubProperty, let value):
            switch hubProperty {
            case .advertisingName:
                nameLabel.text = value.description
            case .firmwareVersion:
                firmwareVersionLabel.text = "F/W: \(value)"
            case .batteryVoltage:
                batteryLabel.text = "Battery: \(value) %"
            default:
                break
            }
            
        default:
            break
        }
    }
}

extension ViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return connectedHubs.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return connectedHubs[row].name ?? "Unknown"
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedHub = connectedHubs[row]
    }
}
