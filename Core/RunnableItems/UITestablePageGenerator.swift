//
//  UITestablePageGenerator.swift
//  AccessibilityGenerator
//
//  Created by Aytuğ Sevgi on 20.09.2021.
//

import Foundation

public final class UITestablePageGenerator: Runnable {
    public func isSatisfied(identifier: String) -> Bool {
        identifier == "forqa"
    }

    private enum ViewType {
        case view
        case viewController
        case cell
    }

    public func execute(lines: NSMutableArray?) {
        self.lines = lines
        conformAccessiblityIdenfiableToView()?.conformUITestablePageToView()?.generateUIElementClass()
    }

    public var lines: NSMutableArray?
    private var className: String = .init()
    private var viewType: ViewType {
        if className.suffix(5).contains("Cell") {
            return .cell
        } else if className.suffix(15).contains("ViewController") {
            return .viewController
        }
        return .view
    }

    private lazy var outletNames: [String.SubSequence] = {
        outlets.compactMap { $0.name }
    }()

    private lazy var outletTypes: [String.SubSequence] = {
        outlets.compactMap { $0.type }
    }()

    private lazy var outlets: [(name: String.SubSequence, type: String.SubSequence)] = {
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String> else { return .init() }
        var outlets = arrayLines.filter { $0.contains("@IBOutlet") }.compactMap { line -> (String.SubSequence, String.SubSequence)? in
            guard let outlet = line.split(separator: " ").first(where: { $0.last == ":" })?.dropLast(),
                  let type = line.split(separator: " ").last?.dropLast(2),
                  type != "NSLayoutConstraint" else { return nil }
            return (outlet, type)
        }
        if viewType == .viewController {
            var mutableClassName = className.replacingOccurrences(of: "Controller", with: "")
            var lowercasedClassName = mutableClassName.prefix(1).lowercased() + mutableClassName.dropFirst()
            outlets.append(("\(lowercasedClassName)", "MainView"))
        }
        outlets = outlets.filter{ (name, type) in
            return !name.contains("Constraint")
        }
        return outlets
    }()

    public static var shared : UITestablePageGenerator { UITestablePageGenerator() }

    private func updateLines(from newLines: [String]) {
        guard let lines = lines else { return }
        lines.removeAllObjects()
        lines.addObjects(from: newLines)
    }

    private func addAccessibilityIdetifiable(to conformableLine: String) -> String {
        var conformableLineWords = conformableLine.split(separator: " ")
        var needComma = false
        let isHasAnyConform = conformableLineWords.count > 3
        if isHasAnyConform && conformableLineWords.contains("AnyObject") {
            conformableLineWords.removeAll { $0 == "AnyObject" }

        } else if isHasAnyConform && conformableLineWords.contains("AnyObject,") {
            conformableLineWords.removeAll { $0 == "AnyObject," }
            needComma = true
        }

        else if !isHasAnyConform {
            conformableLineWords[1].append(":")
        } else {
            conformableLineWords[conformableLineWords.count - 2].append(",")
        }
        if needComma {
            conformableLineWords[conformableLineWords.count - 2].append(",")
        }
        conformableLineWords.insert("AccessibilityIdentifiable", at: conformableLineWords.count - 1 )
        return conformableLineWords.joined(separator: " ")
    }

    private func createUIElements(outletNames: [String.SubSequence?], elementsName: String, isCell: Bool, cellName: String) -> String {
        var elementExtension = "public extension UIElements {\n"
        elementExtension.append("\tenum \(elementsName): String, UIElement {\n")
        elementExtension.append("\t\t// MARK: - \(className)\n")
        for (name, type) in outlets {
            elementExtension.append("\t\tcase \(name)\n")
            if type == "UISearchBar" {
                elementExtension.append("\t\tcase searchTextField\n")
            }
        }
        if isCell {
            elementExtension.append("\t\tcase \(cellName)\n")
        }
        elementExtension.append("\t}\n}")
        return elementExtension
    }

    @discardableResult
    private func generateUIElementPage() -> Self? {
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String>,
              !outlets.isEmpty else { return nil }
        arrayLines.append("\nimport XCTest\n\n")
        let classWithoutSuffix = className.replacingOccurrences(of: "ViewController", with: "")
        arrayLines.append("// MARK: - \(classWithoutSuffix)Screen")
        arrayLines.append("final class \(classWithoutSuffix)Screen: BaseScreen {\n")
        outlets.forEach { (name, type) in
            let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
            arrayLines.append(getElementQuery(elementType: elementType, name: name))
        }

        arrayLines.append("\n\t@discardableResult\n")
        arrayLines.append("\tfunc check\(classWithoutSuffix)Screen() -> Self {\n")
        for (index, name) in outletNames.enumerated() {
            if index == .zero {
                arrayLines.append("\t\twaitForPage(elements: [[\(name): .exist\(outletNames.count == 1 ? "]])\n" : ", ")")
            } else if index == outletNames.count - 1 {
                arrayLines.append("\t\t                        \(name): .exist]])\n")
            } else {
                arrayLines.append("\t\t                        \(name): .exist, ")
            }
        }
        arrayLines.append("\t\treturn self\n\t}\n")
        arrayLines.append("}")
        
        if !outlets.isEmpty {
            arrayLines.append("\n// MARK: - Assertion")
            arrayLines.append("extension \(classWithoutSuffix)Screen {")
            arrayLines.append("}")
            
            arrayLines.append("\n// MARK: - Action")
            arrayLines.append("extension \(classWithoutSuffix)Screen {")
            outlets.forEach { (name, type) in
                let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
                if elementType == .button {
                    var name = String(name)
                    name.uppercaseFirst()
                    arrayLines.append("\t@discardableResult\n")
                    arrayLines.append("\tfunc tap\(name)() -> Self {\n")
                    name.lowercaseFirst()
                    arrayLines.append("\t\texpect(element: \(name), status: .exist).tap()\n")
                    arrayLines.append("\t\treturn self\n\t}\n\n")
                }
            }
            arrayLines.append("}")
        }
        
        updateLines(from: arrayLines)
        return self
    }
    
    private func getElementQuery(elementType: UITestablePageGenerator.UIElementType, name: String.SubSequence) -> String {
        let classWithoutSuffix = className.replacingOccurrences(of: "ViewController", with: "")
        switch elementType {
        case .dolapButton:
            return "\tprivate lazy var \(name) = app.buttons.element(matching: .button, identifier: UIElements.\(classWithoutSuffix)AccessibilityIdentifier.\(name).rawValue)\n"
        default:
            return "\tprivate lazy var \(name) = app.\(elementType)s[UIElements.\(classWithoutSuffix)AccessibilityIdentifier.\(name).rawValue]\n"
        }
    }

    @discardableResult
    private func generateUIElementCell() -> Self? {
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String>,
              !outlets.isEmpty else { return nil }
        arrayLines.append("\nimport XCTest\n\n")
        arrayLines.append("protocol \(className)ElementsProtocol {\n")

        let hasClassPrefix = !className.prefix(3).contains { $0.isLowercase }
        var mutableClassName = className
        if hasClassPrefix {
            mutableClassName.forEach { _ in
                let isUppercasedFirstTwoChars = !mutableClassName.prefix(2).contains { $0.isLowercase }
                guard isUppercasedFirstTwoChars else { return }
                mutableClassName.removeFirst()
            }
        }
        mutableClassName.lowercaseFirst()
        arrayLines.append("\tfunc \(mutableClassName)(at index: Int) -> XCUIElement\n")
        outlets.forEach { (name, type) in
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            arrayLines.append("\tfunc \(mutableClassName)\(mutableElementName)(at index: Int) -> XCUIElement\n")
        }
        mutableClassName.lowercaseFirst()
        arrayLines.append("\tfunc \(mutableClassName)Elements(at index: Int, status: UIStatus) -> [XCUIElement: UIStatus]\n")
        mutableClassName.uppercaseFirst()
        arrayLines.append("\tfunc check\(mutableClassName)(at index: Int, status: UIStatus) -> Self\n")
        arrayLines.append("}\n\n")

        arrayLines.append("final class \(className)Elements: BaseScreen, \(className)ElementsProtocol {\n")
        mutableClassName.lowercaseFirst()
        arrayLines.append("\tfunc \(mutableClassName)(at index: Int) -> XCUIElement {\n")
        arrayLines.append("\t\tapp.cells[String(format: UIElements.\(className)AccessibilityIdentifier.\(mutableClassName).rawValue + \"_%d\", index)].firstMatch\n\t}\n\n")
        outlets.forEach { (name, type) in
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            arrayLines.append("\tfunc \(mutableClassName)\(mutableElementName)(at index: Int = 0) -> XCUIElement {\n")
            let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
            arrayLines.append("\t\t\(mutableClassName)(at: index).\(elementType == .collection ? "collectionView" : "\(elementType)")\(elementType == .switches ? "" : "s")[UIElements.\(className)AccessibilityIdentifier.\(name).rawValue]\n\t}\n\n")
        }
        arrayLines.append("\t@discardableResult\n")
        mutableClassName.lowercaseFirst()
        arrayLines.append("\tfunc \(mutableClassName)Elements(at index: Int = 0, status: UIStatus = .exist) -> [XCUIElement: UIStatus] {\n")
        for (index, name) in outletNames.enumerated() {
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            if index == .zero {
                let suffix = outletNames.count > 1 ? ", " : "]\n\t}\n\n"
                arrayLines.append("\t\t[\(mutableClassName)\(mutableElementName)(at: index): status\(suffix)")
            } else if index == outletNames.count - 1 {
                arrayLines.append("\t\t \(mutableClassName)\(mutableElementName)(at: index): status]\n\t}\n\n")
            } else {
                arrayLines.append("\t\t \(mutableClassName)\(mutableElementName)(at: index): status,")
            }
        }
        arrayLines.append("\t@discardableResult\n")
        mutableClassName.uppercaseFirst()
        arrayLines.append("\tfunc check\(mutableClassName)(at index: Int = 0, status: UIStatus = .exist) -> Self {\n")
        mutableClassName.lowercaseFirst()
        arrayLines.append("\t\twaitForElements(elements: \(mutableClassName)Elements(at: index, status: status))\n")
        arrayLines.append("\t\treturn self\n\t}\n\n")

        mutableClassName.uppercaseFirst()
        arrayLines.append("\t@discardableResult\n")
        arrayLines.append("\tfunc tap\(mutableClassName)(at index: Int) -> Self {\n")

        mutableClassName.lowercaseFirst()
        arrayLines.append("\t\texpect(element: \(mutableClassName)(at: index), status: .exist).tap()\n")
        arrayLines.append("\t\treturn self\n\t}\n")

        outlets.forEach { (name, type) in
            let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
            if elementType == .button {
                arrayLines.append("\n")
                var name = String(name)
                name.uppercaseFirst()
                arrayLines.append("\t@discardableResult\n")
                arrayLines.append("\tfunc tap\(name)(at index: Int) -> Self {\n")
                arrayLines.append("\t\texpect(element: \(mutableClassName)\(name)(at: index), status: .exist).tap()\n")
                arrayLines.append("\t\treturn self\n\t}\n")
            }
        }
        arrayLines.append("}")
        updateLines(from: arrayLines)
        return self
    }

    @discardableResult
    private func generateUIElementView() -> Self? {
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String>,
              !outlets.isEmpty else { return nil }
        arrayLines.append("\nimport XCTest\n")
        arrayLines.append("import AccessibilityKit\n")
        arrayLines.append("import UITestBaseKit\n\n")
        arrayLines.append("public protocol \(className)Elements where Self: Page {\n")

        let hasClassPrefix = !className.prefix(3).contains { $0.isLowercase }
        var mutableClassName = className
        if hasClassPrefix {
            mutableClassName.forEach { _ in
                let isUppercasedFirstTwoChars = !mutableClassName.prefix(2).contains { $0.isLowercase }
                guard isUppercasedFirstTwoChars else { return }
                mutableClassName.removeFirst()
            }
        }
        //arrayLines.append("\tfunc \(mutableClassName)(_ baseElement: XCUIElement, at index: Int) -> XCUIElement\n")
        outlets.forEach { (name, type) in
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            mutableClassName.lowercaseFirst()
            arrayLines.append("\tvar \(mutableClassName)\(mutableElementName): XCUIElement { get }\n")
        }
        mutableClassName.lowercaseFirst()
        arrayLines.append("\n\tfunc \(mutableClassName)Elements(status: UIStatus) -> [XCUIElement: UIStatus]\n")
        mutableClassName.uppercaseFirst()
        arrayLines.append("\tfunc check\(mutableClassName)(status: UIStatus) -> Self\n")
        arrayLines.append("}\n\n")

        arrayLines.append("public extension \(className)Elements {\n")
        outlets.forEach { (name, type) in
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            mutableClassName.lowercaseFirst()
            arrayLines.append("\tvar \(mutableClassName)\(mutableElementName): XCUIElement { ")
            let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
            arrayLines.append("\t\tapp.\(elementType == .collection ? "collectionView" : "\(elementType)")\(elementType == .switches ? "" : "s")[UIElements.\(className)Elements.\(name).rawValue]\n\t}\n")
        }
        arrayLines.append("\n\t@discardableResult\n")
        mutableClassName.lowercaseFirst()
        arrayLines.append("\tfunc \(mutableClassName)Elements(status: UIStatus = .exist) -> [XCUIElement: UIStatus] {\n")
        for (index, name) in outletNames.enumerated() {
            var mutableElementName = String(name)
            mutableElementName.uppercaseFirst()
            if index == .zero {
                let suffix = outletNames.count > 1 ? ", " : "]\n\t}\n\n"
                arrayLines.append("\t\t[\(mutableClassName)\(mutableElementName): status\(suffix)")
            } else if index == outletNames.count - 1 {
                arrayLines.append("\t\t \(mutableClassName)\(mutableElementName): status]\n\t}\n\n")
            } else {
                arrayLines.append("\t\t \(mutableClassName)\(mutableElementName): status,")
            }
        }
        arrayLines.append("\t@discardableResult\n")
        mutableClassName.uppercaseFirst()
        arrayLines.append("\tfunc check\(mutableClassName)(status: UIStatus = .exist) -> Self {\n")
        mutableClassName.lowercaseFirst()
        arrayLines.append("\t\twaitForElements(elements: \(mutableClassName)Elements(status: status))\n")
        arrayLines.append("\t\treturn self\n\t}\n")
        mutableClassName.uppercaseFirst()
        outlets.forEach { (name, type) in
            let elementType = UIElementType.init(rawValue: String(type)) ?? .otherElement
            if elementType == .button {
                arrayLines.append("\n")
                var name = String(name)
                name.uppercaseFirst()
                arrayLines.append("\t@discardableResult\n")
                arrayLines.append("\tpublic func tap\(mutableClassName)\(name)() -> Self {\n")
                arrayLines.append("\t\texpect(element: \(mutableClassName)\(name), status: .exist).tap()\n")
                arrayLines.append("\t\treturn self\n\t}\n")
            }
        }
        arrayLines.append("}")
        updateLines(from: arrayLines)
        return self
    }

    @discardableResult
    private func conformAccessiblityIdenfiableToView() -> Self? {
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String> else { return nil }
        guard let classLine = arrayLines.first(where: { $0.contains("class") && $0.contains(":") }) else { return nil }
        let classLineWords = classLine.split(separator: " ")
        guard let classIndex = classLineWords.firstIndex(of: "class") else { return nil }
        className = String(classLineWords[classIndex + 1])

        className.removeAll { $0 == ":"}
        let interfaceName = className.replacingOccurrences(of: "Controller", with: "")
        //MARK: - Protocol conform AccessibilityIdentifiable
        if let interfaceLine = arrayLines.first(where: { $0.contains("protocol \(interfaceName)") }) {
            if !interfaceLine.contains("AccessibilityIdentifiable") {
                let conformedLine = addAccessibilityIdetifiable(to: interfaceLine)
                guard let interfaceIndex = arrayLines.firstIndex(of: interfaceLine) else { return nil }
                arrayLines.remove(at: abs(interfaceIndex.distance(to: 0)))
                arrayLines.insert(conformedLine, at: abs(interfaceIndex.distance(to: 0)))
            }
        } else if !classLine.contains("AccessibilityIdentifiable") {
            let conformedLine = addAccessibilityIdetifiable(to: classLine)
            guard let interfaceIndex = arrayLines.firstIndex(of: classLine) else { return nil }
            arrayLines.remove(at: abs(interfaceIndex.distance(to: 0)))
            arrayLines.insert(conformedLine, at: abs(interfaceIndex.distance(to: 0)))
        }
        updateLines(from: arrayLines)
        return self
    }

    @discardableResult
    private func conformUITestablePageToView() -> Self? {
        let classWithoutSuffix = className.replacingOccurrences(of: "ViewController", with: "")
        guard let lines = lines,
              var arrayLines = Array(lines) as? Array<String>,
              !outlets.isEmpty else { return nil }
        arrayLines.append("\n// MARK: - UITestable\nextension \(className): UITestablePage {\n")
        arrayLines.append("\ttypealias UIElementType = UIElements.\(classWithoutSuffix)AccessibilityIdentifier\n\n")
        arrayLines.append("\tfunc setAccessibilityIdentifiers() {\n")
        for (name, outletType) in outlets {
            if outletType == "MainView" {
                arrayLines.append("\t\tmakeViewTestable(self.view, using: .\(name))\n")
            } else {
                arrayLines.append("\t\tmakeViewTestable(\(name), using: .\(name))\n")
            }
            if outletType == "UISearchBar" {
                arrayLines.append("\t\tmakeViewTestable(\(name).textfield, using: .searchTextField)\n")
            }
        }
        arrayLines.append("\t}\n")
        var cellName = className
        if viewType == .cell {
            var firstChar = ""
            for char in cellName {
                if char.isLowercase {
                    break
                }
                firstChar = String(cellName.removeFirst())
            }
            cellName = firstChar.lowercased() + cellName
            arrayLines.append("\n\tfunc setAccessibilityIdentifiers(at index: Int) {\n")
            arrayLines.append("\t\tmakeViewTestable(self, using: .\(cellName), index: index)\n")
            arrayLines.append("\t}\n")
        }
        arrayLines.append("}\n\n")
        if !outletNames.isEmpty {
            arrayLines.append(createUIElements(outletNames: outletNames, elementsName: "\(classWithoutSuffix)AccessibilityIdentifier", isCell: viewType == .cell, cellName: cellName))
        }
        updateLines(from: arrayLines)
        return self
    }

    @discardableResult
    private func generateUIElementClass() -> Self? {
        if viewType == .cell {
            return generateUIElementCell()
        } else if viewType == .viewController {
            return generateUIElementPage()
        }
        return generateUIElementView()
    }

    private enum UIElementType: String {
        case button = "UIButton"
        case image = "UIImageView"
        case textField = "UITextField"
        case textView = "UITextView"
        case staticText = "UILabel"
        case collection = "UICollectionView"
        case table = "UITableView"
        case scrollView = "UIScrollView"
        case switches = "UISwitch"
        case dolapButton = "DolapButton"
        case otherElement
    }
}
