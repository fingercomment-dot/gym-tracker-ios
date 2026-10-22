import UIKit

/// First launch: the link to your Gym Tracker in Claude.
final class SetupViewController: UIViewController, UITextFieldDelegate {
    var onOpen: ((URL) -> Void)?
    var onCancel: (() -> Void)?
    var initialText: String?

    private let field = UITextField()
    private let errorLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        let logo = UIImageView(image: UIImage(named: "Logo"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFill
        logo.layer.cornerRadius = 24
        logo.layer.cornerCurve = .continuous
        logo.clipsToBounds = true
        let logoBox = UIView()
        logoBox.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 104),
            logo.heightAnchor.constraint(equalToConstant: 104),
            logo.centerXAnchor.constraint(equalTo: logoBox.centerXAnchor),
            logo.topAnchor.constraint(equalTo: logoBox.topAnchor),
            logo.bottomAnchor.constraint(equalTo: logoBox.bottomAnchor),
        ])

        let title = UILabel()
        title.text = "Gym Tracker"
        title.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 34, weight: .bold))
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center

        let body = UILabel()
        body.text = "Вставь ссылку на своё приложение в Claude — ту, по которой ты его открываешь: claude.ai/artifact/…\n\nВ аккаунт Claude войдёшь один раз. Дальше всё как обычно, только тренировка и таймер отдыха видны на экране блокировки и в Dynamic Island."
        body.font = .preferredFont(forTextStyle: .body)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0

        field.text = initialText
        field.placeholder = "https://claude.ai/artifact/…"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .secondarySystemGroupedBackground
        field.layer.cornerRadius = 12
        field.layer.cornerCurve = .continuous
        field.keyboardType = .URL
        field.textContentType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        field.delegate = self
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 10))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        var pasteConfig = UIButton.Configuration.gray()
        pasteConfig.title = "Вставить из буфера"
        pasteConfig.image = UIImage(systemName: "doc.on.clipboard")
        pasteConfig.imagePadding = 8
        pasteConfig.cornerStyle = .large
        pasteConfig.buttonSize = .large
        let paste = UIButton(configuration: pasteConfig, primaryAction: UIAction { [weak self] _ in self?.pasteLink() })

        var openConfig = UIButton.Configuration.filled()
        openConfig.title = "Открыть"
        openConfig.cornerStyle = .large
        openConfig.buttonSize = .large
        let open = UIButton(configuration: openConfig, primaryAction: UIAction { [weak self] _ in self?.submit() })

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [logoBox, title, body, field, paste, open, errorLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: logoBox)
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(28, after: body)
        stack.setCustomSpacing(16, after: field)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 56),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
        ])

        if onCancel != nil {
            var cancelConfig = UIButton.Configuration.plain()
            cancelConfig.title = "Отмена"
            let cancel = UIButton(configuration: cancelConfig, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })
            cancel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(cancel)
            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
                cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            ])
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }

    private func pasteLink() {
        let board = UIPasteboard.general
        var text: String?
        if board.hasURLs {
            text = board.url?.absoluteString
        } else if board.hasStrings {
            text = board.string
        }
        guard let text, !text.isEmpty else {
            show(error: "В буфере нет ссылки. Скопируй её в Claude и нажми ещё раз.")
            return
        }
        field.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        submit()
    }

    private func submit() {
        guard let url = Self.link(from: field.text ?? "") else {
            show(error: "Это не похоже на ссылку. Нужна ссылка вида https://claude.ai/artifact/…")
            return
        }
        errorLabel.isHidden = true
        view.endEditing(true)
        onOpen?(url)
    }

    private func show(error: String) {
        errorLabel.text = error
        errorLabel.isHidden = false
    }

    /// Takes the first link out of whatever was pasted.
    static func link(from raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var candidate = text
        if let range = text.range(of: #"https?://[^\s"'<>]+"#, options: [.regularExpression, .caseInsensitive]) {
            candidate = String(text[range])
        } else if !text.contains("://") {
            candidate = "https://" + text
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}
