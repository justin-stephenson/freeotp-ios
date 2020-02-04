//
//  URIViewController.swift
//  FreeOTP
//
//  Created by Justin Stephenson on 2/4/20.
//  Copyright © 2020 Fedora Project. All rights reserved.
//

import UIKit

class URIViewController: UIViewController, UINavigationControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource,
                         UITextFieldDelegate {

    var uri = URI()

    var inputUrlc: URLComponents!
    var outputUrlc: URLComponents!

    @IBOutlet weak var issuerTextField: UITextField!
    @IBOutlet weak var accountTextField: UITextField!
    @IBOutlet weak var counterTextField: UITextField!
    @IBOutlet weak var lockSwitch: UISwitch!
    @IBOutlet weak var algorithmPicker: UIPickerView!
    @IBOutlet weak var periodPicker: UIPickerView!
    @IBOutlet weak var digitPicker: UIPickerView!
    @IBOutlet weak var imageButton: UIButton!
    
    var algorithmSelectedValue = ""
    var periodSelectedValue = ""
    var digitSelectedValue = ""
    var counterTextValue = ""

    @IBAction func savePressed(_ sender: UIBarButtonItem) {
        // Construct new URI
        let issuer = issuerTextField.text!
        let account = accountTextField.text!
        outputUrlc.path = "/" + issuer + ":" + account

        var queryItems: [URLQueryItem] = inputUrlc.queryItems ?? []
        var newVal = ""
        for item in uri.queryItems {
            switch (item) {
            case "lock":
                newVal = lockSwitch.isOn ? "true" : "false"
            case "algorithm":
                newVal = algorithmSelectedValue
            case "period":
                newVal = periodSelectedValue
            case "digits":
                newVal = digitSelectedValue
            case "counter":
                newVal = counterTextValue
            default:
                continue
            }

            if newVal != "" {
                let newItem = URLQueryItem(name: item, value: newVal)
                queryItems.append(newItem)
            }
        }

        outputUrlc.queryItems = queryItems
        print("output is \(outputUrlc)")

        // Save Token
        if TokenStore().add(outputUrlc) != nil {
            self.navigationController?.popToRootViewController(animated: true)
        } else {
            // FIXME: Error handling
            print("Invalid token URI!")
        }
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch pickerView.tag {
        case 0:
            algorithmSelectedValue = uri.algorithms[row]
        case 1:
            periodSelectedValue = uri.period[row]
        case 2:
            digitSelectedValue = uri.digits[row]
        default:
            break
        }
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch pickerView.tag {
        case 0:
            return uri.algorithms.count
        case 1:
            return uri.period.count
        case 2:
            return uri.digits.count
        default:
            return 0
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch pickerView.tag {
        case 0:
            return uri.algorithms[row]
        case 1:
            return uri.period[row]
        case 2:
            return uri.digits[row]
        default:
            return ""
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        counterTextValue = textField.text ?? ""
        return true
    }

    func setUIObjects(_ params: URI.Params) {
        // Setup Pickers
        algorithmPicker.selectRow(0, inComponent: 0, animated: false)
        periodPicker.selectRow(1, inComponent: 0, animated: false)
        digitPicker.selectRow(0, inComponent: 0, animated: false)

        if params.algorithm != "" {
            if let index = uri.algorithms.firstIndex(of: params.algorithm) {
                algorithmPicker.selectRow(index, inComponent: 0, animated: false)
            }
            algorithmPicker.isUserInteractionEnabled = false
            algorithmPicker.alpha = 0.5
        }

        if params.period != "" {
            if let index = uri.period.firstIndex(of: params.period) {
                periodPicker.selectRow(index, inComponent: 0, animated: false)
            }
            periodPicker.isUserInteractionEnabled = false
            periodPicker.alpha = 0.5
        }

        if params.digits != "" {
            if let index = uri.digits.firstIndex(of: params.digits) {
                digitPicker.selectRow(index, inComponent: 0, animated: false)
            }
            digitPicker.isUserInteractionEnabled = false
            digitPicker.alpha = 0.5
        }

        // Setup text fields
        if params.issuer != "" {
            issuerTextField.isUserInteractionEnabled = false
            issuerTextField.text = params.issuer
            issuerTextField.alpha = 0.5
        }
        if params.account != "" {
            accountTextField.isUserInteractionEnabled = false
            accountTextField.text = params.account
            accountTextField.alpha = 0.5
        }
        if params.label != "" {
            accountTextField.isUserInteractionEnabled = false
            accountTextField.text = params.label
            accountTextField.alpha = 0.5
        }
        if params.counter != "" {
            counterTextField.isUserInteractionEnabled = false
            counterTextField.text = params.counter
            counterTextField.alpha = 0.5
        }
        
        // Setup lock switch and image
        if params.lock != "" {
            if params.lock.lowercased() == "true" {
                lockSwitch.isUserInteractionEnabled = false
                lockSwitch.isOn = true
                lockSwitch.alpha = 0.5
            } else if params.lock.lowercased() == "false" {
                lockSwitch.isUserInteractionEnabled = false
                lockSwitch.isOn = false
                lockSwitch.alpha = 0.5
            }
        }

        // FIXME: Size?
        let size = CGSize(width: 300, height: 300)
        if params.image != "" {
            ImageDownloader(size).fromURI(params.image, completion: {
                (image: UIImage) -> Void in
                
                self.imageButton.setImage(image, for: .normal)
            })
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        algorithmPicker.delegate = self
        algorithmPicker.dataSource = self
        periodPicker.delegate = self
        periodPicker.dataSource = self
        digitPicker.delegate = self
        digitPicker.dataSource = self
        counterTextField.delegate = self
        self.navigationController?.delegate = self

        print("input is \(inputUrlc)")
        if let inputParams = uri.parseUrlc(inputUrlc) {
            setUIObjects(inputParams)
            outputUrlc = inputUrlc
        } else {
            // Error invalid URI
        }
    }
}
