import Cocoa

class GeneralSettingsView: NSView {
    private let punctuationPopUp = NSPopUpButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        let label = NSTextField(labelWithString: "句読点スタイル:")
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        punctuationPopUp.translatesAutoresizingMaskIntoConstraints = false
        punctuationPopUp.addItems(withTitles: [
            "「、。」（標準）",
            "「，．」（カンマ・ピリオド）"
        ])
        punctuationPopUp.selectItem(at: Settings.shared.punctuationStyle.rawValue)
        punctuationPopUp.target = self
        punctuationPopUp.action = #selector(punctuationStyleChanged(_:))
        addSubview(punctuationPopUp)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            punctuationPopUp.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            punctuationPopUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            punctuationPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    @objc private func punctuationStyleChanged(_ sender: NSPopUpButton) {
        if let style = PunctuationStyle(rawValue: sender.indexOfSelectedItem) {
            Settings.shared.punctuationStyle = style
        }
    }
}
